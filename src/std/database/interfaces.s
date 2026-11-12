package std.database.contracts
import ("std.result"; "std.database")

// Optional declaration-only contracts. Dynamic trait calls are not supported
// by the standalone compiler; std.mysql exposes concrete native client functions.
// open validates configuration and must not imply an established connection.
trait driver {
    func open(std.database.options config) std.result.result[database,std.database.error];
}
trait database {
    func connect() std.result.result[connection,std.database.error];
    func close() std.database.error;
}
trait query {
    func query(std.database.statement request) std.result.result[std.database.rows,std.database.error];
}
trait exec {
    func exec(std.database.statement request) std.result.result[std.database.result,std.database.error];
}
trait connection {
    func ping() std.database.error;
    func query(std.database.statement request) std.result.result[std.database.rows,std.database.error];
    func exec(std.database.statement request) std.result.result[std.database.result,std.database.error];
    func prepare(string sql) std.result.result[prepared_statement,std.database.error];
    func begin() std.result.result[transaction,std.database.error];
    func close() std.database.error;
}
trait transaction {
    func query(std.database.statement request) std.result.result[std.database.rows,std.database.error];
    func exec(std.database.statement request) std.result.result[std.database.result,std.database.error];
    func prepare(string sql) std.result.result[prepared_statement,std.database.error];
    func commit() std.database.error;
    func rollback() std.database.error;
    func close() std.database.error;
}
trait prepared_statement {
    func query(std.database.value[] parameters) std.result.result[std.database.rows,std.database.error];
    func exec(std.database.value[] parameters) std.result.result[std.database.result,std.database.error];
    func close() std.database.error;
}
