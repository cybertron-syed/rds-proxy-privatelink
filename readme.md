## Terraform / RDS_Proxy and PrivateLinkSet up PrivateLinks+Endpoints for RDS


Set up PrivateLink endpoints for userdata and hopper (stage and prod) so that the infra-svcs vpc can access the databases as a local endpoint. 80% of the terraform code for these already exists.

The pattern to follow is documented in this AWS blueprint:

NLB and PrivateLink doc: https://aws.amazon.com/blogs/database/access-amazon-rds-across-vpcs-using-aws-privatelink-and-network-load-balancer/

Use Amazon RDS Proxy and AWS PrivateLink to access Amazon RDS databases across AWS Organizations at American Family Insurance Group | Amazon Web Services 
source: https://aws.amazon.com/blogs/database/use-amazon-rds-proxy-and-aws-privatelink-to-access-amazon-rds-databases-across-aws-organizations-at-american-family-insurance-group/

See infrastructure/modules/rdsprivatelink and infrastructure/stacks/rdsprivatelink for what has been completed. The remainder of the build-out is to add an RDS Proxy to the stack that can connect to RDS instances in public subnets.

The final step is to create interface vpc endpoints in the infra svcs accounts that can connect to the VPC Privatelinks.

Done when the infra-svcs private subnets can access the databases without going to the public internet.

