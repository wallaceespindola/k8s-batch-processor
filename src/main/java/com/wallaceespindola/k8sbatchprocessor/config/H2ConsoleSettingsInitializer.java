package com.wallaceespindola.k8sbatchprocessor.config;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Properties;

/**
 * Pre-populates ~/.h2.server.properties so the H2 console login form
 * shows the correct JDBC URL (jdbc:h2:mem:batchdb) instead of the
 * H2 default (jdbc:h2:~/test).
 *
 * <p>Spring Boot's H2ConsoleAutoConfiguration has no init parameter to
 * override the pre-filled URL — H2 reads saved connection settings from
 * this properties file on disk. Writing it on startup is the only way
 * to configure the default shown in the login form.</p>
 */
@Slf4j
@Component
@ConditionalOnProperty(name = "spring.h2.console.enabled", havingValue = "true")
public class H2ConsoleSettingsInitializer implements ApplicationRunner {

    @Value("${spring.datasource.url:jdbc:h2:mem:batchdb}")
    private String datasourceUrl;

    @Value("${spring.datasource.username:sa}")
    private String datasourceUsername;

    @Override
    public void run(ApplicationArguments args) {
        try {
            Path propsFile = Path.of(System.getProperty("user.home"), ".h2.server.properties");

            Properties props = new Properties();
            if (Files.exists(propsFile)) {
                try (InputStream in = Files.newInputStream(propsFile)) {
                    props.load(in);
                }
            }

            // Strip extra H2 connection params (;KEY=VALUE...) — the base URL is enough
            String baseUrl = datasourceUrl.contains(";")
                    ? datasourceUrl.substring(0, datasourceUrl.indexOf(';'))
                    : datasourceUrl;

            // Format: name|driver|url|user  (H2 WebServer convention)
            props.setProperty("0", "K8s Batch DB|org.h2.Driver|" + baseUrl + "|" + datasourceUsername);

            try (OutputStream out = Files.newOutputStream(propsFile)) {
                props.store(out, "H2 Server Properties");
            }

            log.debug("H2 console pre-configured with URL: {}", baseUrl);

        } catch (Exception e) {
            log.warn("Could not pre-configure H2 console saved settings: {}", e.getMessage());
        }
    }
}
