
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

# Load Target Groups and RDS Proxy Endpoints from environment variables (as JSON)
TARGET_GROUPS = json.loads(os.environ["TARGET_GROUPS"])  # List of target group ARNs
RDS_PROXY_ENDPOINTS = json.loads(os.environ["RDS_PROXY_ENDPOINTS"])  # List of RDS Proxy Endpoints

def get_ip_addresses(endpoint):
    """Resolve multiple IP addresses for the RDS Proxy endpoint."""
    try:
        ip_addresses = socket.gethostbyname_ex(endpoint)[2]
        logger.info(f"Resolved IP addresses for {endpoint}: {ip_addresses}")
        return ip_addresses
    except Exception as e:
        logger.error(f"Error resolving IP addresses for {endpoint}: {e}")
        return []

def update_target_registration(target_group_arn, proxy_endpoint):
    try:
        logger.info(f"Checking target registration for {proxy_endpoint} in target group {target_group_arn}")
        
        # Retrieve the IP addresses of the RDS Proxy DNS endpoint
        proxy_ips = get_ip_addresses(proxy_endpoint)
        
        if not proxy_ips:
            logger.error(f"No IPs found for RDS Proxy endpoint: {proxy_endpoint}")
            return {"success": False, "message": f"No IPs found for RDS Proxy endpoint: {proxy_endpoint}"}
        
        # Retrieve the existing targets in the target group
        targets = elbv2_client.describe_target_health(TargetGroupArn=target_group_arn)
        
        # Get the list of current target IPs in the target group
        current_ips = [
            target["Target"]["Id"]
            for target in targets["TargetHealthDescriptions"]
        ]
        
        # Determine which IPs to deregister (IPs that are not in proxy_ips)
        deregister_ips = [ip for ip in current_ips if ip not in proxy_ips]
        register_ips = [ip for ip in proxy_ips if ip not in current_ips]

        # Deregister the IPs that are no longer valid
        if deregister_ips:
            logger.info(f"Deregistering old target IPs: {deregister_ips}")
            elbv2_client.deregister_targets(
                TargetGroupArn=target_group_arn,
                Targets=[{"Id": ip} for ip in deregister_ips]
            )
        
        # Register the new target IPs
        if register_ips:
            logger.info(f"Registering new target IPs: {register_ips}")
            elbv2_client.register_targets(
                TargetGroupArn=target_group_arn,
                Targets=[{"Id": ip, "Port": 5432} for ip in register_ips]  # Default PostgreSQL port
            )
        
        message = f"Target group {target_group_arn} updated. Registered IPs: {register_ips}, Deregistered IPs: {deregister_ips}"
        logger.info(message)
        return {"success": True, "message": message}
    
    except Exception as e:
        logger.error(f"Error updating target registration: {e}")
        return {"success": False, "message": f"Failed to update targets with error: {e}"}

def lambda_handler(event, context):
    logger.info("Handler invoked")
    
    # Iterate over multiple proxy endpoints and target groups
    for target_group_arn in TARGET_GROUPS:
        for proxy_endpoint in RDS_PROXY_ENDPOINTS:
            result = update_target_registration(target_group_arn, proxy_endpoint)
            
            # If the update failed, return the error immediately
            if not result["success"]:
                status_code = 500
                return {"statusCode": status_code, "body": json.dumps(result["message"])}
    
    # If all updates succeed, return a success response
    logger.info("All target group registrations successfully updated.")
    return {"statusCode": 200, "body": json.dumps("All target groups updated successfully.")}

