# Single-stage image using Swift runtime (simpler, includes libswiftCore)
FROM swift:6.0-jammy

WORKDIR /app

# Copy package and sources into the container
COPY . .

# Build release binary
RUN swift build -c release

# Expose the app port (matches fly.toml internal_port)
EXPOSE 8080

# Run the Vapor server
CMD [".build/release/oftb-server"]
