import logging
import boto3
import os
import socket
import json

# Initialize clients
elbv2_client = boto3.client("elbv2")
rds_client = boto3.client("rds")

# Initialize logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Load RDS Proxy endpoint and Target Group ARN from environment variables
TARGET_GROUP_ARN = os.environ["TARGET_GROUP_ARN"]
# TARGET_GROUP_ARN = 'arn:aws:elasticloadbalancing:us-east-1:406446085161:targetgroup/hopper-proxy-target-group/8679eea621f2993a'
RDS_PROXY_ENDPOINT = os.environ["RDS_PROXY_ENDPOINT"]
# RDS_PROXY_ENDPOINT = 'hopper-postgres-proxy.proxy-c56qui4s6a17.us-east-1.rds.amazonaws.com'

def update_target_registration():
    try:
        logger.info(f"Checking target registration for {RDS_PROXY_ENDPOINT}")
        
        # Retrieve the IP address of the RDS Proxy DNS endpoint
        ip_address = socket.gethostbyname(RDS_PROXY_ENDPOINT)
        
        # Retrieve the existing target of the target group
        targets = elbv2_client.describe_target_health(TargetGroupArn=TARGET_GROUP_ARN)
        
        # Check and update the target group
        current_ip = (
            targets["TargetHealthDescriptions"][0]["Target"]["Id"]
            if targets["TargetHealthDescriptions"]
            else None
        )
        
        if current_ip != ip_address:
            if current_ip:
                # Deregister the current target
                elbv2_client.deregister_targets(
                    TargetGroupArn=TARGET_GROUP_ARN, Targets=[{"Id": current_ip}]
                )

            # Register the new target
            elbv2_client.register_targets(
                TargetGroupArn=TARGET_GROUP_ARN,
                Targets=[{"Id": ip_address, "Port": 5432}],  # Default PostgreSQL port
            )
            message = (
                f"Target group {TARGET_GROUP_ARN} updated. New target IP: {ip_address}"
            )
        else:
            message = (
                f"Target group {TARGET_GROUP_ARN} already up to date. Current target"
                f" IP: {ip_address}"
            )

        logger.info(message)
        return {"success": True, "message": message}
    except Exception as e:
        logger.error(f"Error updating target registration: {e}")
        return {
            "success": False,
            "message": f"Failed to update targets with error: {e}",
        }

def lambda_handler(event, context):
    logger.info("Handler invoked")
    
    # Update the target registration for the RDS Proxy
    result = update_target_registration()
    
    # Return response based on success or failure
    status_code = 200 if result["success"] else 500
    return {"statusCode": status_code, "body": json.dumps(result["message"])}
