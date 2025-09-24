#!/bin/bash
set -e

# Function to initialize PostgreSQL if needed
initialize_postgresql() {
    if [ ! -d "$PGDATA" ]; then
        echo "Initializing PostgreSQL data directory..."
        mkdir -p "$PGDATA"
        chown -R postgres:postgres "$PGDATA"

        # Initialize the database cluster
        su - postgres -c "initdb -D $PGDATA"

        # Configure PostgreSQL settings
        cp /etc/postgresql/postgresql.conf "$PGDATA/postgresql.conf"
        cp /etc/postgresql/pg_hba.conf "$PGDATA/pg_hba.conf"

        # Create replication user
        echo "Creating replication user..."
        su - postgres -c "psql -c \"CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD '${REPLICATION_PASSWORD:-replicator}';\""
    fi
}

# Function to check etcd connectivity
check_etcd() {
    local etcd_host=${ETCD_HOST:-localhost}
    local etcd_port=${ETCD_PORT:-2379}

    echo "Checking etcd connectivity at ${etcd_host}:${etcd_port}..."
    if timeout 10 bash -c "echo quorum | nc ${etcd_host} ${etcd_port}" 2>/dev/null; then
        echo "Etcd is reachable"
        return 0
    else
        echo "Etcd is not reachable, waiting..."
        return 1
    fi
}

# Main execution
main() {
    # Check if etcd is available (with retries)
    local max_retries=30
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        if check_etcd; then
            break
        fi
        echo "Waiting for etcd... ($((max_retries - retry_count)) attempts remaining)"
        sleep 5
        ((retry_count++))
    done

    if [ $retry_count -eq $max_retries ]; then
        echo "Error: Could not connect to etcd after ${max_retries} attempts"
        exit 1
    fi

    # Initialize PostgreSQL if needed
    initialize_postgresql

    # Start Patroni
    exec "$@"
}

# Run main function with arguments
main "$@"
