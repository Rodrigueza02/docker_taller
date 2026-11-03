# REPORTE FORENSE - TALLER DOCKER SEMANA 13

**Proyecto:** eco-air-backend  
**Estudiante:** Maria Juliana Rodriguez Andrade  
**Estudiante ID:** 885309  
**Fecha:** 2026-10-26

---

## TABLA DE IDENTIDAD

### Hash de la Imagen
```bash
docker inspect --format='{{.Id}}' eco-air-backend:1.0.0
```
**Resultado:**
```
sha256:33594045c1f987a0fe45e76ad38e11ba1e9f262dfcbc4caecf6c0e922af2258c
```

### Variable de Entorno Inyectada
```bash
docker exec eco_air_active env | grep OPERATOR_ID
```
**Resultado:**
```
OPERATOR_ID=885309
```

### Consumo Final Calibrado
```bash
docker stats --no-stream eco_air_active
```
**Resultado:**
```
CONTAINER ID   NAME             CPU %     MEM USAGE / LIMIT   MEM %     NET I/O         BLOCK I/O   PIDS
6fbd1628ee5f   eco_air_active   0.14%     167.9MiB / 256MiB   65.59%    1.17kB / 126B   0B / 0B     30
```

---

## RETO 1: CONSTRUCCIÓN MULTIETAPA CON HUELLA ESTRICTA

### Comando de Construcción Ejecutado
```bash
docker build --build-arg STUDENT_ID="885309" -t eco-air-backend:1.0.0 .
```

### Características Implementadas
- Etapa 1 (builder): `maven:3.9.6-eclipse-temurin-17-alpine`
- Aislamiento de dependencias con `mvn dependency:go-offline -B`
- ARG STUDENT_ID declarado
- Empaquetado sin pruebas (`-DskipTests`)
- Etapa 2 (runtime): `eclipse-temurin:17-jre-alpine`
- Usuario sin privilegios: `sensor_user` (UID 10001), grupo `sensorgroup`
- Variables JVM ergonómicas: `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0`
- ENV OPERATOR_ID=${STUDENT_ID}
- USER sensor_user antes del ENTRYPOINT

### Salida del Build
```
[+] Building 108.8s (19/19) FINISHED                          docker:default
 => [builder 1/6] FROM docker.io/library/maven:3.9.6-eclipse-temurin-17-alpine
 => [builder 2/6] WORKDIR /build
 => [builder 3/6] COPY pom.xml .
 => [builder 4/6] RUN mvn dependency:go-offline -B                       85.9s
 => [builder 5/6] COPY src ./src
 => [builder 6/6] RUN mvn clean package -DskipTests -B                    7.0s
 => [stage-1 1/5] FROM docker.io/library/eclipse-temurin:17-jre-alpine
 => [stage-1 2/5] RUN addgroup -S sensorgroup && adduser -S -u 10001 -G sensorgroup sensor_user
 => [stage-1 3/5] WORKDIR /app
 => [stage-1 4/5] COPY --from=builder /build/target/eco-air-backend.jar /app/app.jar
 => [stage-1 5/5] RUN chown -R sensor_user:sensorgroup /app
 => naming to docker.io/library/eco-air-backend:1.0.0
✅ Construcción exitosa
```

---

## RETO 2: AUDITORÍA FORENSE Y COMPROBACIÓN DE VULNERABILIDADES

### 2.1 Verificación del Desacoplamiento de Capas

```bash
docker history --human --format "table {{.Size}}\t{{.CreatedBy}}" eco-air-backend:1.0.0
```

**Evidencia:**
```
SIZE      CREATED BY
0B        ENTRYPOINT ["sh" "-c" "java $JAVA_OPTS -jar …
0B        USER sensor_user
0B        EXPOSE [8080/tcp]
0B        ENV OPERATOR_ID=885309
0B        ARG STUDENT_ID=885309
0B        ENV JAVA_OPTS=-XX:+UseContainerSupport -XX:M…
47.5MB    RUN /bin/sh -c chown -R sensor_user:sensorgr…
47.5MB    COPY /build/target/eco-air-backend.jar /app/…
8.19kB    WORKDIR /app
41kB      RUN /bin/sh -c addgroup -S sensorgroup &&   …
0B        ENTRYPOINT ["/__cacert_entrypoint.sh"]
12.3kB    COPY --chmod=755 entrypoint.sh /__cacert_ent…
12.3kB    RUN /bin/sh -c set -eux; echo "Verifying…
141MB     RUN /bin/sh -c set -eux; ARCH="$(apk --p…
0B        ENV JAVA_VERSION=jdk-17.0.20.1+1
37.9MB    RUN /bin/sh -c set -eux; apk add --no-ca…
0B        ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_AL…
0B        ENV PATH=/opt/java/openjdk/bin:/usr/local/sb…
0B        ENV JAVA_HOME=/opt/java/openjdk
0B        CMD ["/bin/sh"]
9.08MB    ADD alpine-minirootfs-3.24.3-x86_64.tar.gz / …
```

**Análisis:** La imagen final contiene únicamente JRE (~141MB) y el JAR compilado (~47.5MB). No existen capas de Maven, JDK ni código fuente, lo que confirma el desacoplamiento multietapa exitoso.

---

### 2.2 Inspección del Proceso del Host (Aislamiento de Privilegios)

```bash
docker run -d --name eco_air_active -p 8080:8080 eco-air-backend:1.0.0
docker top eco_air_active -o pid,user,comm
```

**Evidencia:**
```
PID                 USER                COMMAND
1558                10001               java
```

**Análisis:** El proceso `java` se ejecuta bajo el UID 10001 (`sensor_user`), no como root. Esto confirma el aislamiento de privilegios y reduce la superficie de ataque del contenedor.

---

### 2.3 Test de Penetración: Comprobación de Inmutabilidad de Runtime

```bash
docker exec eco_air_active touch /etc/crontab_fake
```

**Evidencia:**
```
touch: cannot touch '/etc/crontab_fake': Permission denied
```

**Análisis:** El contenedor se ejecuta con `sensor_user` sin privilegios de escritura en directorios del sistema. Un atacante no puede crear ni modificar archivos críticos como scripts de crontab, lo que previene ataques de persistencia.

---

### 2.4 Auditoría de Artefactos de Desarrollo

```bash
docker exec eco_air_active which mvn
docker exec eco_air_active find / -name "*.java" 2>/dev/null
```

**Evidencia:**
```
(sin salida - Maven NO está presente en la imagen)
(sin salida - No existen archivos .java del código fuente)
```

**Análisis:** La construcción multietapa garantiza que Maven y el código fuente `.java` no se copian a la imagen de runtime. Solo el JAR compilado está disponible en producción, reduciendo drásticamente el tamaño y la superficie de ataque.

---

## RETO 3: CALIBRACIÓN DE CGROUPS Y CAPTURA DEL ASESINO OOM

### 3.1 Inducción del Colapso por Memoria (OOMKilled)

```bash
docker run -d --name eco_air_crash -m 48m eco-air-backend:1.0.0
sleep 15
docker inspect eco_air_crash --format='Status: {{.State.Status}} | ExitCode: {{.State.ExitCode}} | OOMKilled: {{.State.OOMKilled}}'
```

**Evidencia:**
```
Status: exited | ExitCode: 137 | OOMKilled: true
```

**Análisis:** Con 48MB el kernel Linux activó el OOM Killer y terminó el proceso con señal SIGKILL (exit code 137). Spring Boot + JVM requieren significativamente más memoria para inicializar el contexto de aplicación. `OOMKilled: true` confirma que la terminación fue por límite de memoria excedido.

---

### 3.2 Calibración del Límite Operativo Mínimo

#### Prueba con 256MB

```bash
docker run -d --name eco_air_active -m 256m -p 8080:8080 eco-air-backend:1.0.0
docker logs --timestamps eco_air_active | grep "Started EcoAirApplication"
```

**Evidencia de inicio:**
```
2026-10-29T16:17:37.536357098Z  Started EcoAirApplication in 3.251 seconds (process running for 3.69)
```

**Evidencia docker stats:**
```bash
docker stats --no-stream eco_air_active
```
```
CONTAINER ID   NAME             CPU %     MEM USAGE / LIMIT   MEM %     NET I/O         BLOCK I/O   PIDS
6fbd1628ee5f   eco_air_active   0.14%     167.9MiB / 256MiB   65.59%    1.17kB / 126B   0B / 0B     30
```

**Tabla de Calibración Iterativa:**

| Memoria | Estado | Tiempo de inicio | MEM USAGE / LIMIT | MEM % |
|---------|--------|-----------------|-------------------|-------|
| 48 MB   | ❌ OOMKilled (ExitCode 137) | — | — | — |
| 256 MB  | ✅ Funcional | 3.251 segundos | 167.9MiB / 256MiB | 65.59% |

**Umbral mínimo operativo: 256 MB**

**Análisis:** Con 256MB la aplicación inicia correctamente en 3.251 segundos (muy por debajo del límite de 15 segundos requerido) y se mantiene estable con un uso del 65.59% de la memoria asignada.

---

## CONCLUSIONES

- **Umbral mínimo:** 256 MB — inicio en 3.251s, uso estable de 167.9MiB (65.59%)
- **Recomendado para producción:** 384–512 MB para absorber picos de tráfico de alertas ambientales
- **Seguridad validada:** Usuario `sensor_user` (UID 10001) confirmado, sin escritura en `/etc/`
- **Imagen optimizada:** Solo JRE + JAR, sin Maven ni código fuente
- **OOM Killer verificado:** ExitCode 137 con 48MB confirma el comportamiento del kernel con cgroups

---

**Hash de la imagen:** `sha256:33594045c1f987a0fe45e76ad38e11ba1e9f262dfcbc4caecf6c0e922af2258c`  
**Timestamp de compilación:** `2026-10-29T16:17:37Z`  
**Operador ID:** `885309`
