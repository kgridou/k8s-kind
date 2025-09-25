package com.example.myapp.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;

@Configuration
public class AppConfiguration {

    @Value("${app.api.external-key}")
    private String externalApiKey;

    @Value("${app.api.jwt-secret}")
    private String jwtSecret;

    @Value("${app.features.vault-integration:false}")
    private boolean vaultIntegrationEnabled;

    @Value("${app.features.database-enabled:false}")
    private boolean databaseEnabled;

    // Getters
    public String getExternalApiKey() {
        return externalApiKey;
    }

    public String getJwtSecret() {
        return jwtSecret;
    }

    public boolean isVaultIntegrationEnabled() {
        return vaultIntegrationEnabled;
    }

    public boolean isDatabaseEnabled() {
        return databaseEnabled;
    }

    // Configuration info methods
    public boolean isProperlyConfigured() {
        return externalApiKey != null &&
                !externalApiKey.equals("default-key") &&
                jwtSecret != null &&
                !jwtSecret.equals("default-secret");
    }

    public String getConfigurationSource() {
        return isProperlyConfigured() ? "vault" : "defaults";
    }
}