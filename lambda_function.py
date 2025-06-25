import json
import time
import uuid
from datetime import datetime

def lambda_handler(event, context):
    """
    Lambda function to test reserved concurrency behavior.
    This function simulates processing time for concurrency testing.
    """
    
    # Generate unique execution ID
    execution_id = str(uuid.uuid4())[:8]
    
    # Get current timestamp
    timestamp = datetime.utcnow().isoformat()
    
    # Fixed processing time for concurrency testing (2.5 seconds)
    processing_time = 2.5
    
    # Simulate processing time
    time.sleep(processing_time)
    
    # Extract request information
    request_id = context.aws_request_id if context else "local-test"
    
    # Prepare response
    response_body = {
        "execution_id": execution_id,
        "timestamp": timestamp,
        "request_id": request_id,
        "processing_time": processing_time,
        "message": "Lambda executed successfully",
        "remaining_time": context.get_remaining_time_in_millis() if context else 0
    }
    
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type"
        },
        "body": json.dumps(response_body)
    } 