%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Basho Technologies, Inc.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(ts_simple_recompile_ddl).

-behavior(riak_test).

-include_lib("eunit/include/eunit.hrl").

-export([confirm/0]).
-define(TABLE, ?MODULE).
-define(KV_MODULE, riak_kv_compile_tab).

confirm() ->
    {Cluster, _Conn} = ts_util:cluster_and_connect(single),
    Node = hd(Cluster),
    lists:foreach(
        fun(Table) ->
            DDL = create_table_sql(Table),
            ts_util:create_and_activate_bucket_type(Cluster, DDL, Table)
        end, test_tables()),
    rt:stop(Node),
    simulate_old_dets_entries(),
    rt:start(Node),
    timer:sleep(15000),
    verify_resulting_dets_entries(),
    pass.

open_dets() ->
    FileDir = rtdev:riak_data(1),
    FilePath = filename:join(FileDir, [?KV_MODULE, ".dets"]),
    {ok, ?TABLE} = dets:open_file(?TABLE, [{type, set}, {repair, force}, {file, FilePath}]).

simulate_old_dets_entries() ->
    open_dets(),
    Pid = spawn_link(fun() -> ok end),
    Pid2 = spawn_link(fun() -> ok end),
    Pid3 = spawn_link(fun() -> ok end),
    Table1DDL = sql_to_ddl(create_table_sql("Table1")),
    Table2DDL = sql_to_ddl(create_table_sql("Table2")),
    Table3DDL = sql_to_ddl(create_table_sql("Table3")),
    ok = dets:insert(?TABLE, {<<"Table1">>, Table1DDL, Pid, compiled}),
    ok = dets:insert(?TABLE, {<<"Table2">>, 1, Table2DDL, Pid2, compiled}),
    ok = dets:insert(?TABLE, {<<"Table3">>, 1, Table3DDL, Pid3, compiling}),
    dets:close(?TABLE).

verify_resulting_dets_entries() ->
    wait_for_recompilation(),
    %% Requery the DETS table to ensure new version exists
    open_dets(),
    lists:foreach(fun(T) ->
        ?assertEqual(
            [[2, compiled]],
            dets:match(?TABLE, {T,'$1','_','_','$2'}))
        end, test_tables()),
    dets:close(?TABLE).

wait_for_recompilation() ->
    open_dets(),
    lager:debug("DETS =~p", [dets:match(?TABLE, {'$1', '$2','$3','$4','$5'})]),
    Pids = dets:match(?TABLE, {'_','_','_','$1',compiling}),
    dets:sync(?TABLE),
    dets:close(?TABLE),
    %% Set up monitoring for compiling jobs
    MonitorRefs = lists:foldl(fun([CompilerPid], Acc) ->
                                [monitor(process, CompilerPid)|Acc]
                              end, [], Pids),
    %% Receive completed compilation messages for each process
    lists:foreach(fun(Ref) ->
        receive
            {'DOWN', Ref, _Type, _Object, _Info} ->
                ok
        after 10000 ->
            ?assertEqual("DDL compiliation timed out", timeout)
        end
    end, MonitorRefs).

test_tables() ->
    [<<"Table1">>,<<"Table2">>,<<"Table3">>].

create_table_sql(TableName) ->
    lists:flatten(io_lib:format("CREATE TABLE ~s ("
    " datum       varchar   not null,"
    " someseries  varchar   not null,"
    " time        timestamp not null,"
    " PRIMARY KEY ((datum, someseries, quantum(time, 15, 'm')), "
    " datum, someseries, time))", [TableName])).

sql_to_ddl(SQL) ->
    Lexed = riak_ql_lexer:get_tokens(SQL),
    {ok, {DDL, _Props}} = riak_ql_parser:parse(Lexed),
    DDL.