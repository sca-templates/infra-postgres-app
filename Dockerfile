# ---- Stage 1: build pgvector from source ----
FROM postgres:18-alpine AS builder

RUN apk add --no-cache \
    git \
    build-base \
    postgresql-dev \
    clang19 \
    llvm19

RUN git clone --branch v0.8.2 --depth 1 https://github.com/pgvector/pgvector.git /tmp/pgvector

WORKDIR /tmp/pgvector
RUN make && make install

# ---- Stage 2: clean final image ----
FROM postgres:18-alpine

COPY --from=builder /usr/local/lib/postgresql/vector.so /usr/local/lib/postgresql/
COPY --from=builder /usr/local/share/postgresql/extension/vector* /usr/local/share/postgresql/extension/