plugins {
    java
    application
}

group = "pl.tostrowski.lightsail"
version = "0.1.0"

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

dependencies {
    implementation("software.amazon.awscdk:aws-cdk-lib:2.260.0")
    implementation("software.constructs:constructs:10.6.0")
}

application {
    mainClass = "pl.tostrowski.lightsail.SharedInfraApp"
}
