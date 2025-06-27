import json
import time
import uuid
import os
from datetime import datetime

# Track cold start time
_cold_start_time = time.time()
# Sleep to simulate initialization time
time.sleep(2)
print("Lambda function initialized")
_cold_start_time = time.time() - _cold_start_time

def lambda_handler(event, context):
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
    # Detect if provisioned concurrency was used
    initialization_type = os.environ.get("AWS_LAMBDA_INITIALIZATION_TYPE", "on-demand")
    provisioned_concurrency = initialization_type == "provisioned-concurrency"
    # Cold start logic: only True if not provisioned concurrency and this is the first invocation
    if not hasattr(lambda_handler, "_has_run"):
        lambda_handler._has_run = False
    is_first_invocation = not lambda_handler._has_run
    lambda_handler._has_run = True
    cold_start = is_first_invocation and not provisioned_concurrency
    # Prepare response
    response_body = {
        "execution_id": execution_id,
        "timestamp": timestamp,
        "request_id": request_id,
        "processing_time": processing_time,
        "cold_start_time": _cold_start_time if cold_start else 0,
        "cold_start": cold_start,
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
 