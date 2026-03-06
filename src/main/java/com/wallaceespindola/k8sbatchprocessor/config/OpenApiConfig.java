package com.wallaceespindola.k8sbatchprocessor.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class OpenApiConfig {

    @Bean
    public OpenAPI openAPI() {
        return new OpenAPI()
                .info(new Info()
                        .title("K8s Batch Processor API")
                        .description("Kubernetes-native Spring Batch processor for distributed bank account processing. " +
                                     "Generate accounts and watch them processed in parallel across multiple pods in real-time.")
                        .version("1.0.0")
                        .contact(new Contact()
                                .name("Wallace Espindola")
                                .email("wallace.espindola@gmail.com")
                                .url("https://github.com/wallaceespindola"))
                        .license(new License()
                                .name("Apache 2.0")
                                .url("https://www.apache.org/licenses/LICENSE-2.0")));
    }
}
