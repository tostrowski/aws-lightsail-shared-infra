package pl.tostrowski.lightsail;

import software.amazon.awscdk.StackProps;

public final class SharedPostgresStackProps implements StackProps {
    private final software.amazon.awscdk.Environment env;

    private SharedPostgresStackProps(Builder builder) {
        this.env = builder.env;
    }

    @Override
    public software.amazon.awscdk.Environment getEnv() {
        return env;
    }

    public static Builder builder() {
        return new Builder();
    }

    public static final class Builder {
        private software.amazon.awscdk.Environment env;

        public Builder env(software.amazon.awscdk.Environment env) {
            this.env = env;
            return this;
        }

        public SharedPostgresStackProps build() {
            return new SharedPostgresStackProps(this);
        }
    }
}
