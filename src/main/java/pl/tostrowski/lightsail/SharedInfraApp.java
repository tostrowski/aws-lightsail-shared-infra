package pl.tostrowski.lightsail;

import software.amazon.awscdk.App;
import software.amazon.awscdk.Environment;

public final class SharedInfraApp {
    private SharedInfraApp() {
    }

    public static void main(String[] args) {
        App app = new App();

        Environment environment = Environment.builder()
                .account(firstNonBlank(System.getenv("CDK_DEFAULT_ACCOUNT"), System.getenv("AWS_ACCOUNT_ID")))
                .region(firstNonBlank(System.getenv("CDK_DEFAULT_REGION"), System.getenv("AWS_REGION"), "eu-west-1"))
                .build();

        new SharedPostgresStack(app, "LightsailSharedPostgresStack",
                SharedPostgresStackProps.builder()
                        .env(environment)
                        .build());

        app.synth();
    }

    private static String firstNonBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) {
                return value;
            }
        }
        return null;
    }
}
