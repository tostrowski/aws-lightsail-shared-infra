package pl.tostrowski.lightsail;

import java.util.List;

import software.amazon.awscdk.CfnOutput;
import software.amazon.awscdk.CfnParameter;
import software.amazon.awscdk.CfnTag;
import software.amazon.awscdk.Stack;
import software.amazon.awscdk.services.lightsail.CfnDatabase;
import software.constructs.Construct;

public final class SharedPostgresStack extends Stack {
    public SharedPostgresStack(Construct scope, String id, SharedPostgresStackProps props) {
        super(scope, id, props);

        String databaseName = contextString("databaseName");
        String elficoDatabaseName = contextString("elficoDatabaseName");
        String czyjafakturkaDatabaseName = contextString("czyjafakturkaDatabaseName");

        CfnParameter masterUserPassword = CfnParameter.Builder.create(this, "MasterUserPassword")
                .type("String")
                .description("Initial Lightsail PostgreSQL master user password. Store it outside Git.")
                .noEcho(true)
                .minLength(8)
                .maxLength(63)
                .build();

        CfnDatabase database = CfnDatabase.Builder.create(this, "SharedPostgresDatabase")
                .relationalDatabaseName(databaseName)
                .availabilityZone(contextString("availabilityZone"))
                .relationalDatabaseBlueprintId(contextString("blueprintId"))
                .relationalDatabaseBundleId(contextString("bundleId"))
                .masterDatabaseName(contextString("masterDatabaseName"))
                .masterUsername(contextString("masterUsername"))
                .masterUserPassword(masterUserPassword.getValueAsString())
                .publiclyAccessible(contextBoolean("publiclyAccessible"))
                .backupRetention(contextBoolean("backupRetention"))
                .preferredBackupWindow(contextString("preferredBackupWindow"))
                .preferredMaintenanceWindow(contextString("preferredMaintenanceWindow"))
                .tags(List.of(
                        CfnTag.builder().key("Project").value("shared-lightsail-postgres").build(),
                        CfnTag.builder().key("ManagedBy").value("aws-cdk").build()))
                .build();

        output("DatabaseResourceName", databaseName);
        output("DatabaseArn", database.getAttrDatabaseArn());
        output("Region", getRegion());
        output("AvailabilityZone", contextString("availabilityZone"));
        output("BundleId", contextString("bundleId"));
        output("BlueprintId", contextString("blueprintId"));
        output("PubliclyAccessibleByDefault", String.valueOf(contextBoolean("publiclyAccessible")));
        output("ElficoDatabaseName", elficoDatabaseName);
        output("CzyjafakturkaDatabaseName", czyjafakturkaDatabaseName);
        output("ElficoAppUserSecretName", secretName(databaseName, elficoDatabaseName));
        output("CzyjafakturkaAppUserSecretName", secretName(databaseName, czyjafakturkaDatabaseName));
    }

    private String contextString(String key) {
        Object value = getNode().tryGetContext(key);
        if (value != null && !value.toString().isBlank()) {
            return value.toString();
        }
        return switch (key) {
            case "databaseName" -> "shared-postgres";
            case "availabilityZone" -> "eu-west-1a";
            case "blueprintId" -> "postgres_18";
            case "bundleId" -> "micro_2_0";
            case "masterDatabaseName" -> "postgres";
            case "masterUsername" -> "postgres_admin";
            case "preferredBackupWindow" -> "02:00-02:30";
            case "preferredMaintenanceWindow" -> "sun:03:00-sun:03:30";
            case "elficoDatabaseName" -> "elfico";
            case "czyjafakturkaDatabaseName" -> "czyjafakturka";
            default -> throw new IllegalArgumentException("Missing required CDK context value: " + key);
        };
    }

    private boolean contextBoolean(String key) {
        Object value = getNode().tryGetContext(key);
        if (value instanceof Boolean booleanValue) {
            return booleanValue;
        }
        if (value == null || value.toString().isBlank()) {
            return switch (key) {
                case "publiclyAccessible" -> false;
                case "backupRetention" -> true;
                default -> throw new IllegalArgumentException("Missing required CDK context value: " + key);
            };
        }
        return Boolean.parseBoolean(value.toString());
    }

    private void output(String id, String value) {
        CfnOutput.Builder.create(this, id).value(value).build();
    }

    private String secretName(String lightsailDatabaseName, String logicalDatabaseName) {
        return "/lightsail/" + lightsailDatabaseName + "/" + logicalDatabaseName + "/app-user";
    }
}
