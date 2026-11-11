package std.database

// Contract declarations only. Current standalone compiler cannot emit dynamic
// trait calls (see doc/database/audit.md). No fake concrete drivers are provided.
struct options {
    string host
    int port
    string database_name
    string user
    string password
    int connect_timeout_ms
    int read_timeout_ms
    int write_timeout_ms
    int max_packet_bytes
    string tls_server_name
    string tls_ca_file
}
trait database {
    func connect() (connection,error);
    func close() error;
}
trait query {
    func query(statement request) (rows,error);
}
trait exec {
    func exec(statement request) (result,error);
}
trait connection {
    func ping() error;
    func query(statement request) (rows,error);
    func exec(statement request) (result,error);
    func prepare(string sql) (prepared_statement,error);
    func begin() (transaction,error);
    func close() error;
}
trait transaction {
    func query(statement request) (rows,error);
    func exec(statement request) (result,error);
    func prepare(string sql) (prepared_statement,error);
    func commit() error;
    func rollback() error;
    func close() error;
}
trait prepared_statement {
    func query(value[] parameters) (rows,error);
    func exec(value[] parameters) (result,error);
    func close() error;
}
