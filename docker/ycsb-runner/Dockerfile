# YCSB Runner — containerized YCSB benchmark tool
# Joins the same Docker network as target DB to resolve hostnames natively
# Base: Eclipse Temurin JDK 11 (matches local dev environment)
#
# Supports:
#   - MongoDB (native binding bundled with YCSB 0.17)
#   - Cassandra (native binding bundled with YCSB 0.17)
#   - CockroachDB / PostgreSQL (via JDBC binding + PostgreSQL JDBC driver)

FROM eclipse-temurin:11-jdk-jammy

LABEL maintainer="PhamAnhQuoc-HTTT"
LABEL description="YCSB 0.17.0 runner for distributed DB benchmarks (Mongo/Cassandra/CockroachDB)"

# Install runtime tools
# python2 is required because YCSB's bin/ycsb launcher is Python 2
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    python2 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/python2 /usr/bin/python

# Download and extract YCSB 0.17.0
WORKDIR /opt
RUN curl -fsSL -o ycsb.tar.gz \
    https://github.com/brianfrankcooper/YCSB/releases/download/0.17.0/ycsb-0.17.0.tar.gz \
    && tar -xzf ycsb.tar.gz \
    && rm ycsb.tar.gz \
    && mv ycsb-0.17.0 ycsb

# Add PostgreSQL JDBC driver (needed for CockroachDB benchmark via jdbc-binding)
# CockroachDB speaks PostgreSQL wire protocol -> use pgjdbc driver
ARG PGJDBC_VERSION=42.7.3
RUN curl -fsSL -o /opt/ycsb/jdbc-binding/lib/postgresql-${PGJDBC_VERSION}.jar \
    https://jdbc.postgresql.org/download/postgresql-${PGJDBC_VERSION}.jar

ENV YCSB_HOME=/opt/ycsb
ENV PATH=$YCSB_HOME/bin:$PATH

WORKDIR /workspace

ENTRYPOINT ["ycsb"]
CMD ["--help"]