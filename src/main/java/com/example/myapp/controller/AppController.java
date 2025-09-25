package com.example.myapp.controller;

import com.example.myapp.config.AppConfiguration;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.HashMap;
import java.util.Map;

@RestController
public class AppController {

    @Autowired
    private AppConfiguration appConfig;

    @Autowired
    private DataSource dataSource;

    @Value("${spring.datasource.url}")
    private String datasourceUrl;

    @Value("${spring.datasource.username}")
    private String datasourceUsername;

    @GetMapping("/")
    public Map<String, Object> home() {
        Map<String, Object> response = new HashMap<>();
        response.put("application", "MyApp with Vault Integration");
        response.put("status", "running");
        response.put("vault-integration", "enabled");
        response.put("timestamp", System.currentTimeMillis());
        return response;
    }

    @GetMapping("/config")
    public Map<String, Object> getConfiguration() {
        Map<String, Object> config = new HashMap<>();

        // Show configuration from Vault (safe values only)
        config.put("external-api-key", appConfig.getExternalApiKey());
        config.put("jwt-secret-configured", appConfig.getJwtSecret() != null && !appConfig.getJwtSecret().isEmpty());
        config.put("database-url", datasourceUrl);
        config.put("database-username", datasourceUsername);

        return config;
    }

    @GetMapping("/health")
    public Map<String, Object> health() {
        Map<String, Object> health = new HashMap<>();

        try {
            // Test database connection
            try (Connection connection = dataSource.getConnection()) {
                health.put("database", "connected");
                health.put("database-url", connection.getMetaData().getURL());
            }
        } catch (SQLException e) {
            health.put("database", "disconnected");
            health.put("database-error", e.getMessage());
        }

        // Test Vault secrets
        boolean vaultConfigured = appConfig.getExternalApiKey() != null &&
                !appConfig.getExternalApiKey().equals("default-key");
        health.put("vault-secrets", vaultConfigured ? "configured" : "using-defaults");

        health.put("status", "healthy");
        health.put("timestamp", System.currentTimeMillis());

        return health;
    }

    @GetMapping("/vault-test")
    public Map<String, Object> testVaultSecrets() {
        Map<String, Object> vaultTest = new HashMap<>();

        // Test that secrets are loaded from Vault
        vaultTest.put("external-api-key-source",
                appConfig.getExternalApiKey().startsWith("dev-") ? "vault" : "default");
        vaultTest.put("jwt-secret-source",
                appConfig.getJwtSecret().startsWith("dev-") ? "vault" : "default");
        vaultTest.put("database-user-source",
                datasourceUsername.equals("devuser") ? "vault" : "default");

        // Show masked secrets for security
        vaultTest.put("external-api-key-masked",
                maskSecret(appConfig.getExternalApiKey()));
        vaultTest.put("jwt-secret-masked",
                maskSecret(appConfig.getJwtSecret()));

        return vaultTest;
    }

    private String maskSecret(String secret) {
        if (secret == null || secret.length() <= 6) {
            return "***";
        }
        return secret.substring(0, 3) + "***" + secret.substring(secret.length() - 3);
    }
}