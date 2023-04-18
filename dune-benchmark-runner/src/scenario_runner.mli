type t

val create : monorepo_path:string -> t
val run_watch_mode_scenarios : t -> rpc_client:Dune_rpc_client.t -> unit Lwt.t
val undo_all_changes : t -> unit

val convert_durations_into_benchmark_results :
  t -> int list -> Benchmark_result.t list
