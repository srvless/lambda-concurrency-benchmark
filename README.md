# Lambda Concurrency Test Dashboard

A comprehensive testing framework to demonstrate AWS Lambda reserved concurrency behavior by sending parallel requests and visualizing throttling effects.

## 🎯 Purpose

This project demonstrates how AWS Lambda reserved concurrency works by:
- Setting up a Lambda function with configurable reserved concurrency (default: 5)
- Sending 100 parallel requests to show that only 5 execute concurrently
- The remaining 95 requests get throttled (HTTP 429 errors)
- Providing a beautiful web UI to visualize results

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Web UI        │    │  Flask Backend   │    │  API Gateway    │
│  (Dashboard)    │◄──►│ (Parallel Reqs)  │◄──►│   + Lambda      │
│                 │    │                  │    │ (Concurrency=5) │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 📁 Project Structure

```
lambda_best_practice/
├── lambda_function.py          # AWS Lambda function code
├── backend/
│   ├── app.py                 # Flask backend for parallel requests
│   └── templates/
│       └── index.html         # Web UI dashboard
├── terraform/
│   └── main.tf               # Infrastructure as Code
├── requirements.txt          # Python dependencies
├── deploy.sh                # Deployment script
├── results/                 # Test results storage
└── README.md               # This file
```

## 🚀 Quick Start

### Prerequisites

1. **AWS CLI** configured with appropriate permissions
2. **Terraform** installed
3. **Python 3.9+** installed
4. **Basic AWS knowledge** (Lambda, API Gateway, IAM)

### Step 1: Deploy Infrastructure

```bash
# Make deployment script executable
chmod +x deploy.sh

# Deploy everything (Lambda + API Gateway)
./deploy.sh deploy
```

This will:
- Package the Lambda function
- Create AWS resources using Terraform
- Set reserved concurrency to 5
- Output the API Gateway URL

### Step 2: Start the Web Interface

```bash
# Install Python dependencies
pip install -r requirements.txt

# Start Flask backend
cd backend
python app.py
```

### Step 3: Run Tests

1. Open http://localhost:5000 in your browser
2. Paste the API Gateway URL from Step 1
3. Configure test parameters:
   - **Number of Requests**: 100 (default)
4. Click "🚀 Run Concurrency Test"

The dashboard will automatically detect the concurrency settings from your test results - no need to manually specify them!

## 📊 Understanding the Results

### Expected Behavior with Reserved Concurrency = 5

- **Successful Requests**: ~5-10 (only these execute within concurrency limit)
- **Throttled Requests**: ~90-95 (HTTP 429 - rate limited)
- **Success Rate**: ~5-10%

### Expected Behavior with Unreserved Concurrency

- **Successful Requests**: ~95-100 (no artificial limits)
- **Throttled Requests**: ~0-5 (only natural AWS account limits)
- **Success Rate**: ~95-100%

### Key Metrics Displayed

| Metric | Description |
|--------|-------------|
| **Total Requests** | Number of parallel requests sent |
| **Successful** | Requests that completed (HTTP 200) |
| **Throttled** | Requests rejected due to concurrency limits (HTTP 429) |
| **Success Rate** | Percentage of successful requests |
| **Reserved Concurrency** | Lambda function's concurrency limit |
| **Avg Response Time** | Average time for successful requests |

## 🔧 Advanced Usage

### Change Concurrency Settings

```bash
# Update to different reserved concurrency limits
./deploy.sh update-concurrency 5   # 5 reserved concurrency
./deploy.sh update-concurrency 10  # 10 reserved concurrency
./deploy.sh update-concurrency 50  # 50 reserved concurrency

# Use unreserved concurrency (no limits)
./deploy.sh update-concurrency unreserved

# Then re-run tests to see the difference
```

### Test Different Scenarios

1. **Scenario 1**: 5 reserved concurrency, 100 requests → ~5% success (95% throttled)
2. **Scenario 2**: 10 reserved concurrency, 100 requests → ~10% success (90% throttled)
3. **Scenario 3**: 50 reserved concurrency, 100 requests → ~50% success (50% throttled)
4. **Scenario 4**: Unreserved concurrency, 100 requests → ~95-100% success (minimal throttling)

### View Historical Results

- All test results are automatically saved in `results/` folder
- Web UI shows test history
- Click on previous tests to compare results

## 🎨 Web Dashboard Features

- **Real-time Progress**: Shows test execution status
- **Visual Charts**: Pie chart showing success/failure distribution
- **Detailed Table**: Individual request results with timing
- **Test History**: Compare multiple test runs
- **Responsive Design**: Works on desktop and mobile

## 📋 API Endpoints

The Flask backend provides these endpoints:

- `GET /` - Web dashboard
- `POST /api/test` - Run concurrency test
- `GET /api/results` - Get current results
- `GET /api/results/files` - List historical results
- `GET /api/results/file/<filename>` - Get specific test results

## 🛠️ Troubleshooting

### Common Issues

1. **"No API Gateway URL"**
   ```bash
   # Re-run deployment
   ./deploy.sh deploy
   ```

2. **"AWS credentials not configured"**
   ```bash
   aws configure
   ```

3. **"Terraform not found"**
   ```bash
   # Install Terraform
   brew install terraform  # macOS
   # or download from terraform.io
   ```

4. **High success rate (not showing throttling)**
   - Verify Lambda reserved concurrency is set correctly
   - Check if requests are truly parallel
   - Ensure API Gateway throttling isn't interfering

### Debug Commands

```bash
# Check Terraform outputs
cd terraform && terraform output

# Test API Gateway directly
curl -X POST <API_GATEWAY_URL> -d '{"test": true}'

# Check Lambda logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/concurrency-test
```

## 🧹 Cleanup

```bash
# Destroy all AWS resources
./deploy.sh destroy
```

## 📚 Learning Objectives

After running this demo, you'll understand:

1. **Reserved Concurrency**: How it limits simultaneous executions
2. **Throttling Behavior**: What happens when limits are exceeded
3. **API Gateway Integration**: How it handles Lambda responses
4. **Parallel Request Patterns**: Best practices for load testing
5. **Monitoring & Visualization**: How to analyze concurrency patterns

## 🤝 Contributing

Feel free to submit issues and enhancement requests!

## 📄 License

This project is for educational purposes. Use responsibly and be mindful of AWS costs.

---

**Happy Testing! 🚀** 