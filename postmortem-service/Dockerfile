# syntax=docker/dockerfile:1.24
# Packages the jar Maven built; it does not build it (backlog #0-141, ADR-0030). The jar comes from a build
# outside Docker: in CI from build-and-test, the jar its `verify` tested (the `service-jars` artifact, put back
# into postmortem-service/target/); locally from `make dev-up` or `make build` (`./mvnw clean package -DskipTests`). The
# code is compiled and its dependencies downloaded once, by Maven with its own repository and cache, and
# never again inside Docker. A missing jar fails the COPY, and two (an old version left in target/) the RUN.

# ---- Layers ----
# The jar extracted into Spring Boot's layers (dependencies, loader, snapshot dependencies, application),
# each copied below as an image layer of its own: a change to the code alone changes the application layer
# (under 1 MB), and the dependencies' layer (over 100 MB) is reused by the build cache and a registry.
FROM eclipse-temurin:25.0.5_8-jre-alpine AS layers

WORKDIR /layers

COPY postmortem-service/target/postmortem-service-*.jar jar/

RUN set -- jar/*.jar \
    && if [ "$#" -ne 1 ]; then echo "expected one postmortem-service jar in target/, found $#: $*" >&2; exit 1; fi \
    && java -Djarmode=tools -jar "$1" extract --layers --launcher --destination extracted

# ---- Runtime stage ----
FROM eclipse-temurin:25.0.5_8-jre-alpine

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Owned by root, not writable by appuser: the service cannot change its own code (until #0-141 app.jar
# belonged to appuser). Least changing first, so the layers above them stay cached.
COPY --from=layers /layers/extracted/dependencies/ ./
COPY --from=layers /layers/extracted/spring-boot-loader/ ./
COPY --from=layers /layers/extracted/snapshot-dependencies/ ./
COPY --from=layers /layers/extracted/application/ ./

USER appuser

EXPOSE 8085

# JarLauncher runs the extracted layers as `java -jar` ran the jar; arguments are passed to main unchanged
# (auth-service's break-glass-mfa-reset subcommand, backlog #0-88).
ENTRYPOINT ["java", \
  "-XX:+UseContainerSupport", \
  "-XX:MaxRAMPercentage=75.0", \
  "-Djava.security.egd=file:/dev/./urandom", \
  "org.springframework.boot.loader.launch.JarLauncher"]
