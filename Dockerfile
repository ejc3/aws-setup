FROM hashicorp/terraform:latest

# Install AWS CLI, MySQL client, CA certificates, and other useful tools
RUN apk add --no-cache \
    aws-cli \
    mysql-client \
    mariadb-connector-c \
    ca-certificates \
    bash \
    curl \
    jq \
    vim

# Download AWS RDS CA bundle
RUN curl -o /usr/local/share/amazon-rds-ca-cert.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

# Copy AWS login script
COPY aws-login.sh /usr/local/bin/aws-login.sh
RUN chmod +x /usr/local/bin/aws-login.sh

# Set working directory
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]
