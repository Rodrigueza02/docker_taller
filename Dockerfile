# ========================================
# Etapa 1: Builder (Compilación)
# Estudiante: Maria Juliana Rodriguez Andrade - 885309
# ========================================
FROM maven:3.9.6-eclipse-temurin-17-alpine AS builder

# Argumento de construcción obligatorio con ID del estudiante
ARG STUDENT_ID

WORKDIR /build

# Copiar solo pom.xml primero para aprovechar caché de dependencias
COPY pom.xml .

# Descargar dependencias offline (optimización de caché)
RUN mvn dependency:go-offline -B

# Copiar código fuente
COPY src ./src

# Empaquetar aplicación omitiendo pruebas
RUN mvn clean package -DskipTests -B

# ========================================
# Etapa 2: Runtime (Producción)
# ========================================
FROM eclipse-temurin:17-jre-alpine

# Crear grupo y usuario sin privilegios
RUN addgroup -S sensorgroup && \
    adduser -S -u 10001 -G sensorgroup sensor_user

# Directorio de trabajo
WORKDIR /app

# Copiar JAR desde etapa builder
COPY --from=builder /build/target/eco-air-backend.jar /app/app.jar

# Cambiar titularidad a usuario sin privilegios
RUN chown -R sensor_user:sensorgroup /app

# Variables de entorno ergonómicas para JVM
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:InitialRAMPercentage=50.0 -Djava.security.egd=file:/dev/./urandom"

# Inyectar ID del estudiante como variable de entorno
ARG STUDENT_ID
ENV OPERATOR_ID=${STUDENT_ID}

# Exponer puerto
EXPOSE 8080

# Cambiar a usuario sin privilegios
USER sensor_user

# Punto de entrada
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app/app.jar"]
