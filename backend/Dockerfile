FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -q -B dependency:go-offline
COPY src ./src
RUN mvn -q -B package -DskipTests

FROM eclipse-temurin:21-jre
WORKDIR /app
# Usuário sem privilégios: a API não precisa de root
RUN useradd --system --uid 10001 loja && mkdir -p /app/media && chown -R loja /app
COPY --from=build /app/target/loja-api-*.jar app.jar
USER loja
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "app.jar"]
