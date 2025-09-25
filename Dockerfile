FROM eclipse-temurin:17-jre-alpine

# Create app user
RUN addgroup -g 1001 -S appuser && \
    adduser -u 1001 -S appuser -G appuser

# Set working directory
WORKDIR /app

# Copy the JAR file
COPY target/*.jar app.jar

# Copy certificate for Vault TLS (will be mounted as volume in K8s)
RUN mkdir -p /etc/ssl/certs/vault

# Change ownership
RUN chown -R appuser:appuser /app /etc/ssl/certs/vault

# Switch to non-root user
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1

# Expose port
EXPOSE 8080

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]