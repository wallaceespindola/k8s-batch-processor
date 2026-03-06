package com.wallaceespindola.k8sbatchprocessor;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableAsync;

@SpringBootApplication
@EnableAsync
public class K8sBatchProcessorApplication {

    public static void main(String[] args) {
        SpringApplication.run(K8sBatchProcessorApplication.class, args);
    }
}
