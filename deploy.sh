#!/bin/bash

# Lambda Concurrency Test Deployment Script
set -e

echo "🚀 Starting Lambda Concurrency Test Deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are installed
check_requirements() {
    print_status "Checking requirements..."
    
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install Terraform first."
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI first."
        exit 1
    fi
    
    if ! command -v zip &> /dev/null; then
        print_error "zip is not installed. Please install zip first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    print_status "All requirements satisfied ✅"
}

# Deploy infrastructure
deploy_infrastructure() {
    print_status "Deploying infrastructure with Terraform..."
    
    cd terraform
    
    # Initialize Terraform
    terraform init
    
    # Plan deployment
    print_status "Planning Terraform deployment..."
    terraform plan
    
    # Apply deployment
    print_status "Applying Terraform deployment..."
    terraform apply -auto-approve
    
    # Get outputs
    API_URL=$(terraform output -raw api_gateway_url)
    LAMBDA_NAME=$(terraform output -raw lambda_function_name)
    RESERVED_CONCURRENCY=$(terraform output -raw reserved_concurrency)
    
    cd ..
    
    print_status "Infrastructure deployed successfully ✅"
    echo ""
    echo "📋 Deployment Information:"
    echo "   API Gateway URL: $API_URL"
    echo "   Lambda Function: $LAMBDA_NAME"
    echo "   Reserved Concurrency: $RESERVED_CONCURRENCY"
    echo ""
}

# Test the deployment
test_deployment() {
    print_status "Testing deployment..."
    
    # Test API Gateway endpoint
    if curl -s -f "$API_URL" > /dev/null; then
        print_status "API Gateway endpoint is accessible ✅"
    else
        print_warning "API Gateway endpoint test failed"
    fi
}

# Update concurrency setting
update_concurrency() {
    local concurrency=$1
    
    if [ -z "$concurrency" ]; then
        print_error "Concurrency value not provided"
        return 1
    fi
    
    if [ "$concurrency" = "unreserved" ]; then
        print_status "Updating Lambda to use unreserved concurrency (no limits)..."
        cd terraform
        terraform apply -var="use_unreserved_concurrency=true" -auto-approve
        cd ..
        print_status "Lambda updated to unreserved concurrency ✅"
    else
        print_status "Updating Lambda reserved concurrency to $concurrency..."
        cd terraform
        terraform apply -var="reserved_concurrency=$concurrency" -var="use_unreserved_concurrency=false" -auto-approve
        cd ..
        print_status "Reserved concurrency updated to $concurrency ✅"
    fi
}

# Trigger provisioned concurrency
setup_provisioned_concurrency() {
    print_status "Setting up provisioned concurrency..."
    cd terraform
    terraform apply -var="use_provisioned_concurrency=true" -auto-approve -replace=archive_file.lambda_zip
    cd ..
    print_status "Provisioned concurrency setup ✅"
}

# Main deployment function
main_deploy() {
    check_requirements
    deploy_infrastructure
    test_deployment
    
    print_status "🎉 Deployment completed successfully!"
    echo ""
    echo "🔗 Next steps:"
    echo "   1. Copy the API Gateway URL: $API_URL"
    echo "   2. Start the Flask backend: python backend/app.py"
    echo "   3. Open http://localhost:5000 in your browser"
    echo "   4. Paste the API URL and run your concurrency tests"
    echo ""
    echo "💡 To change reserved concurrency:"
    echo "   ./deploy.sh update-concurrency <number>"
}

# Handle command line arguments
case "${1:-deploy}" in
    "deploy")
        main_deploy
        ;;
    "update-concurrency")
        if [ -z "$2" ]; then
            print_error "Usage: $0 update-concurrency <concurrency_number|unreserved>"
            print_error "Examples:"
            print_error "  $0 update-concurrency 5"
            print_error "  $0 update-concurrency 50"
            print_error "  $0 update-concurrency unreserved"
            exit 1
        fi
        update_concurrency "$2"
        ;;
    "setup-provisioned-concurrency")
        setup_provisioned_concurrency
        ;;
    "test")
        # Get API URL from Terraform output
        cd terraform
        API_URL=$(terraform output -raw api_gateway_url 2>/dev/null || echo "")
        cd ..
        
        if [ -z "$API_URL" ]; then
            print_error "No deployed infrastructure found. Run './deploy.sh deploy' first."
            exit 1
        fi
        
        test_deployment
        ;;
    "destroy")
        print_warning "This will destroy all AWS resources created by this project."
        read -p "Are you sure? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cd terraform
            terraform destroy -auto-approve
            cd ..
            print_status "Infrastructure destroyed ✅"
        else
            print_status "Destruction cancelled"
        fi
        ;;
    "help"|"-h"|"--help")
        echo "Lambda Concurrency Test Deployment Script"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  deploy                                Deploy complete infrastructure (default)"
        echo "  update-concurrency <num|unreserved>  Update Lambda concurrency settings"
        echo "  package                               Package Lambda function only"
        echo "  test                                  Test deployed infrastructure"
        echo "  destroy                               Destroy all AWS resources"
        echo "  help                                  Show this help message"
        echo ""
        echo "Concurrency Examples:"
        echo "  ./deploy.sh update-concurrency 5         # Set reserved concurrency to 5"
        echo "  ./deploy.sh update-concurrency 50        # Set reserved concurrency to 50"
        echo "  ./deploy.sh update-concurrency unreserved # Use unreserved concurrency (no limits)"
        echo ""
        ;;
    *)
        print_error "Unknown command: $1"
        echo "Run '$0 help' for usage information"
        exit 1
        ;;
esac 