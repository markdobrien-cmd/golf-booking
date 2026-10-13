# Network module

Builds the private network that the EKS cluster and the database live in.

```
                    internet
                       │
               Internet gateway
                       │
        ┌──────────────┴──────────────┐
  public 10.0.240.0/24          public 10.0.241.0/24      load balancer only
   (eu-west-1a)  └── NAT gateway   (eu-west-1b)
        │                             │
  private 10.0.0.0/19           private 10.0.32.0/19      EKS nodes, pods, Aurora
   (eu-west-1a)                  (eu-west-1b)
```

- **Public subnets** route to the internet gateway, so the internet can reach what's in them.
  Only the load balancer goes there.
- **Private subnets** have no route in from the internet. Their outbound traffic (pulling
  images, calling AWS APIs) leaves through the NAT gateway, which never accepts connections in.
- **Why /19 for private:** with VPC CNI each pod gets a real VPC address, so pods use addresses
  fast. A /19 has 8,192; a /24 has 256.
- **Why one NAT gateway:** each one costs about $0.05 an hour. One per zone survives a zone
  failure; for a demo that's not worth doubling the cost.

## Exercise: write the subnets

`main.tf` has an empty "Subnets" section. Everything else in the module already refers to
`aws_subnet.public` and `aws_subnet.private`, so `terraform validate` fails until you add them.

`tests/network.tftest.hcl` is the spec. Run it offline (no AWS login needed):

```bash
cd infra/modules/network
terraform init -backend=false
terraform test
```

Write two resources, `aws_subnet.public` and `aws_subnet.private`, until all 5 tests pass.

Hints, open one at a time:

<details><summary>1. How do I make one subnet per zone?</summary>

`count = var.az_count` creates that many copies. Inside the block, `count.index` is 0, 1, …
and `local.azs[count.index]` is the zone for that copy.
</details>

<details><summary>2. How do I get the address ranges without typing them?</summary>

`cidrsubnet(prefix, newbits, netnum)` carves a smaller range out of a bigger one. Try it in
`terraform console`: `cidrsubnet("10.0.0.0/16", 3, 1)` and `cidrsubnet("10.0.0.0/16", 8, 240)`.
</details>

<details><summary>3. Which arguments does a subnet need?</summary>

`vpc_id`, `availability_zone`, `cidr_block`, and for public ones `map_public_ip_on_launch`.
Look up `aws_subnet` in the AWS provider docs on registry.terraform.io.
</details>

<details><summary>4. What about the tags?</summary>

The AWS Load Balancer Controller looks for subnets tagged `kubernetes.io/role/elb = "1"`
(public) or `kubernetes.io/role/internal-elb = "1"` (private). A `Name` tag makes them readable
in the console.
</details>

When the tests pass, run `terraform fmt` and commit on this branch.
