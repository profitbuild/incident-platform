package com.incidentplatform.notification.support;

import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.context.ApplicationContextInitializer;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.PropertySource;
import org.springframework.core.io.ClassPathResource;

import java.io.IOException;
import java.io.UncheckedIOException;

/**
 * For tests that check what the shipped {@code application.yml} configures
 * (backlog #0-103, #0-104): the environment is the file alone, every
 * {@code ${VAR:default}} left to its default, so no variable of the machine
 * running the test changes what is checked.
 */
public final class ApplicationYml {

    private ApplicationYml() {
    }

    public static void only(ConfigurableEnvironment environment) {
        environment.getPropertySources().stream().map(PropertySource::getName).toList()
                .forEach(environment.getPropertySources()::remove);
        addLast(environment);
    }

    /**
     * application.yml below everything the environment already has, so a test's
     * own {@code @TestPropertySource} overrides only what it names (third review
     * of #0-104: a test pinning a copy of the file's settings could drift from it).
     */
    public static final class Initializer
            implements ApplicationContextInitializer<ConfigurableApplicationContext> {

        @Override
        public void initialize(ConfigurableApplicationContext context) {
            addLast(context.getEnvironment());
        }
    }

    public static void addLast(ConfigurableEnvironment environment) {
        try {
            new YamlPropertySourceLoader()
                    .load("application.yml", new ClassPathResource("application.yml"))
                    .forEach(environment.getPropertySources()::addLast);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
