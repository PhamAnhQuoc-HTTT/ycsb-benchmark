# YCSB Runner — containerized YCSB benchmark tool
# Joins the same Docker network as target DB to resolve hostnames natively
# Base: Eclipse Temurin JDK 11 (matches local dev environment)

FROM eclipse-temurin:11-jdk-jammy

# Metadata
LABEL maintainer="PhamAnhQuoc-HTTT"
LABEL description="YCSB 0.17.0 runner for distributed DB benchmarks"

# Install minimal tools needed at runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    python2 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Make python2 available as `python` (YCSB ycsb script expects python)
RUN ln -s /usr/bin/python2 /usr/bin/python

# Download and extract YCSB 0.17.0
WORKDIR /opt
RUN curl -fsSL -o ycsb.tar.gz \
    https://github.com/brianfrankcooper/YCSB/releases/download/0.17.0/ycsb-0.17.0.tar.gz \
    && tar -xzf ycsb.tar.gz \
    && rm ycsb.tar.gz \
    && mv ycsb-0.17.0 ycsb

ENV YCSB_HOME=/opt/ycsb
ENV PATH=$YCSB_HOME/bin:$PATH

# Working directory for benchmark output
WORKDIR /workspace

# Default entrypoint: ycsb script
# Override CMD when running: docker run ... ycsb-runner load mongodb -P ...
ENTRYPOINT ["ycsb"]
CMD ["--help"]