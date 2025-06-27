from flask import Flask, request, jsonify, render_template, Response
import requests
import json
import os
import time
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading
from collections import defaultdict
import queue

app = Flask(__name__)

# Global variables to store test results
test_results = []
test_lock = threading.Lock()
# Queue for real-time updates
update_queue = queue.Queue()
active_test = False

def create_results_directory():
    """Create results directory if it doesn't exist"""
    if not os.path.exists('results'):
        os.makedirs('results')

@app.route('/')
def index():
    """Serve the main UI page"""
    return render_template('index.html')

@app.route('/api/test/stream')
def test_stream():
    """Server-Sent Events endpoint for real-time test updates"""
    def event_stream():
        while True:
            try:
                # Get update from queue with timeout
                update = update_queue.get(timeout=1)
                yield f"data: {json.dumps(update)}\n\n"
                update_queue.task_done()
            except queue.Empty:
                # Send heartbeat to keep connection alive
                yield "data: {\"type\": \"heartbeat\"}\n\n"
                # Stop if no active test
                if not active_test:
                    break
    
    response = Response(event_stream(), mimetype='text/event-stream')
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['Connection'] = 'keep-alive'
    response.headers['Access-Control-Allow-Origin'] = '*'
    return response

@app.route('/api/test', methods=['POST'])
def run_concurrency_test():
    """Run concurrency test with specified parameters"""
    global active_test
    data = request.get_json()
    
    # Extract parameters
    api_url = data.get('api_url', '')
    num_requests = int(data.get('num_requests', 100))
    
    if not api_url:
        return jsonify({'error': 'API URL is required'}), 400
    
    # Set active test flag
    active_test = True
    
    # Clear previous results and queue
    global test_results
    with test_lock:
        test_results = []
    
    # Clear the update queue
    while not update_queue.empty():
        try:
            update_queue.get_nowait()
        except queue.Empty:
            break
    
    # Send initial update
    update_queue.put({
        'type': 'test_started',
        'total_requests': num_requests,
        'message': f'Starting test with {num_requests} concurrent requests...'
    })
    
    # Run the test
    test_id = datetime.now().strftime('%Y%m%d_%H%M%S')
    
    # Use a barrier to ensure all threads start simultaneously
    barrier = threading.Barrier(num_requests)
    completed_requests = 0
    completed_lock = threading.Lock()
    
    def make_request(request_id):
        """Make a single request to the Lambda function"""
        nonlocal completed_requests
        
        # Wait for all threads to be ready
        barrier.wait()
        
        start_time = time.time()
        try:
            response = requests.post(
                api_url,
                json={'request_id': request_id, 'test_id': test_id},
                timeout=35  # Slightly longer than Lambda timeout
            )
            end_time = time.time()
            
            result = {
                'request_id': request_id,
                'status_code': response.status_code,
                'response_time': round(end_time - start_time, 3),
                'success': response.status_code == 200,
                'timestamp': datetime.now().isoformat(),
                'error': None
            }
            
            if response.status_code == 200:
                try:
                    response_data = response.json()
                    result['lambda_execution_id'] = response_data.get('execution_id', 'unknown')
                    result['lambda_timestamp'] = response_data.get('timestamp', 'unknown')
                    # Add cold start info if present
                    result['cold_start'] = response_data.get('cold_start', None)
                    result['cold_start_time'] = response_data.get('cold_start_time', None)
                except:
                    result['lambda_execution_id'] = 'parse_error'
                    result['lambda_timestamp'] = 'parse_error'
                    result['cold_start'] = None
                    result['cold_start_time'] = None
            else:
                result['error'] = response.text[:200]  # Limit error message length
                result['cold_start'] = None
                result['cold_start_time'] = None
                
        except requests.exceptions.Timeout:
            end_time = time.time()
            result = {
                'request_id': request_id,
                'status_code': 408,
                'response_time': round(end_time - start_time, 3),
                'success': False,
                'timestamp': datetime.now().isoformat(),
                'error': 'Request timeout',
                'lambda_execution_id': 'timeout',
                'lambda_timestamp': 'timeout',
                'cold_start': None,
                'cold_start_time': None
            }
        except Exception as e:
            end_time = time.time()
            result = {
                'request_id': request_id,
                'status_code': 0,
                'response_time': round(end_time - start_time, 3),
                'success': False,
                'timestamp': datetime.now().isoformat(),
                'error': str(e)[:200],
                'lambda_execution_id': 'error',
                'lambda_timestamp': 'error',
                'cold_start': None,
                'cold_start_time': None
            }
        
        # Add result to global results
        with test_lock:
            test_results.append(result)
        
        # Update completed count and send progress update
        with completed_lock:
            completed_requests += 1
            current_completed = completed_requests
        
        # Send real-time update
        successful_so_far = len([r for r in test_results if r['success']])
        update_queue.put({
            'type': 'progress',
            'completed': current_completed,
            'total': num_requests,
            'successful': successful_so_far,
            'failed': current_completed - successful_so_far,
            'latest_result': result,
            'progress_percent': round((current_completed / num_requests) * 100, 1)
        })
        
        return result
    
    # Execute requests in parallel with simultaneous start
    start_test_time = time.time()
    
    update_queue.put({
        'type': 'requests_starting',
        'message': f'All {num_requests} requests are being sent simultaneously...'
    })
    
    with ThreadPoolExecutor(max_workers=num_requests) as executor:
        # Submit all requests at once
        futures = [
            executor.submit(make_request, i) 
            for i in range(1, num_requests + 1)
        ]
        
        # Wait for all requests to complete
        for future in as_completed(futures):
            try:
                result = future.result()
            except Exception as exc:
                print(f'Request generated an exception: {exc}')
    
    end_test_time = time.time()
    total_test_time = round(end_test_time - start_test_time, 3)
    
    # Analyze results
    with test_lock:
        successful_requests = [r for r in test_results if r['success']]
        failed_requests = [r for r in test_results if not r['success']]
        throttled_requests = failed_requests
        
        # Cold start stats
        cold_starts = [r for r in successful_requests if r.get('cold_start')]
        num_cold_starts = len(cold_starts)
        avg_cold_start_time = round(sum(r.get('cold_start_time', 0) or 0 for r in cold_starts) / num_cold_starts, 3) if num_cold_starts > 0 else 0
        
        # Detect concurrency type based on results
        success_rate = round(len(successful_requests) / len(test_results) * 100, 2)
        
        if success_rate > 80:
            reserved_concurrency_value = 'unreserved'
        elif success_rate < 15:
            estimated_concurrency = max(1, round(len(successful_requests)))
            reserved_concurrency_value = f'~{estimated_concurrency} (estimated)'
        else:
            estimated_concurrency = max(1, round(len(successful_requests) * 1.2))
            reserved_concurrency_value = f'~{estimated_concurrency} (estimated)'
        
        # Calculate statistics
        stats = {
            'test_id': test_id,
            'timestamp': datetime.now().isoformat(),
            'total_requests': len(test_results),
            'successful_requests': len(successful_requests),
            'failed_requests': len(failed_requests),
            'throttled_requests': len(throttled_requests),
            'success_rate': success_rate,
            'total_test_time': total_test_time,
            'reserved_concurrency': reserved_concurrency_value,
            'avg_response_time': round(
                sum(r['response_time'] for r in successful_requests) / max(len(successful_requests), 1), 3
            ),
            'min_response_time': min((r['response_time'] for r in successful_requests), default=0),
            'max_response_time': max((r['response_time'] for r in successful_requests), default=0),
            'cold_starts': num_cold_starts,
            'avg_cold_start_time': avg_cold_start_time
        }
        
        # Send completion update
        update_queue.put({
            'type': 'test_completed',
            'stats': stats,
            'results': test_results[:50],
            'message': f'Test completed! {len(successful_requests)}/{len(test_results)} requests succeeded'
        })
        
        # Save results to file
        create_results_directory()
        result_file = f'results/test_{test_id}.json'
        with open(result_file, 'w') as f:
            json.dump({
                'stats': stats,
                'results': test_results
            }, f, indent=2)
        
        # Mark test as inactive
        active_test = False
        
        return jsonify({
            'stats': stats,
            'results': test_results[:50],
            'result_file': result_file
        })

@app.route('/api/results')
def get_results():
    """Get current test results"""
    with test_lock:
        return jsonify({
            'results': test_results,
            'count': len(test_results)
        })

@app.route('/api/results/files')
def list_result_files():
    """List all result files"""
    create_results_directory()
    try:
        files = []
        for filename in os.listdir('results'):
            if filename.endswith('.json'):
                filepath = os.path.join('results', filename)
                with open(filepath, 'r') as f:
                    data = json.load(f)
                    stats = data.get('stats', {})
                    files.append({
                        'filename': filename,
                        'test_id': stats.get('test_id', 'unknown'),
                        'timestamp': stats.get('timestamp', 'unknown'),
                        'total_requests': stats.get('total_requests', 0),
                        'success_rate': stats.get('success_rate', 0),
                        'reserved_concurrency': stats.get('reserved_concurrency', 'unknown'),
                        'cold_starts': stats.get('cold_starts', None),
                        'avg_cold_start_time': stats.get('avg_cold_start_time', None)
                    })
        # Sort by filename (which includes timestamp)
        files.sort(key=lambda x: x['filename'], reverse=True)
        return jsonify(files)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/results/file/<filename>')
def get_result_file(filename):
    """Get specific result file"""
    try:
        filepath = os.path.join('results', filename)
        with open(filepath, 'r') as f:
            data = json.load(f)
        return jsonify(data)
    except Exception as e:
        return jsonify({'error': str(e)}), 404

if __name__ == '__main__':
    create_results_directory()
    app.run(debug=True, host='0.0.0.0', port=5000) 