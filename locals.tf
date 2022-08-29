locals {
  instance-userdata = <<EOF
#!/bin/bash
yum install httpd -y
service httpd start
hostname -i | sudo tee /var/www/html/index.html
EOF
  tags = {
    Name = "test-tf-asg"
  }
}