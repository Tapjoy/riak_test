%% -------------------------------------------------------------------
%%
%% Copyright (c) 2013 Basho Technologies, Inc.
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
-module(rt_config).
-include_lib("eunit/include/eunit.hrl").

-export([
         get/1,
         get/2,
         config_or_os_env/1,
         config_or_os_env/2,
         get_os_env/1,
         get_os_env/2,
         load/2,
         set/2,
         set_conf/2,
         set_advanced_conf/2,
         update_app_config/2,
         version_to_path/1
]).

-define(HARNESS, (rt_config:get(rt_harness))).
-define(CONFIG_NAMESPACE, riak_test).
-define(RECEIVE_WAIT_TIME_KEY, rt_max_receive_wait_time).
-define(DEFAULT_VERSION_KEY, default_version).
-define(PREVIOUS_VERSION_KEY, previous_version).
-define(LEGACY_VERSION_KEY, legacy_version).
-define(DEFAULT_VERSION, head).
-define(PREVIOUS_VERSION, "1.4.12").
-define(LEGACY_VERSION, "1.3.4").

%% @doc Get the value of an OS Environment variable. The arity 1 version of
%%      this function will fail the test if it is undefined.
get_os_env(Var) ->
    case get_os_env(Var, undefined) of
        undefined ->
            lager:error("ENV['~s'] is not defined", [Var]),
            ?assert(false);
        Value -> Value
    end.

%% @doc Get the value of an OS Evironment variable. The arity 2 version of
%%      this function will return the Default if the OS var is undefined.
get_os_env(Var, Default) ->
    case os:getenv(Var) of
        false -> Default;
        Value -> Value
    end.

%% @doc Load the configuration from the specified config file.
load(Config, undefined) ->
    load(Config, filename:join([os:getenv("HOME"), ".riak_test.config"]));
load(undefined, ConfigFile) ->
    load_dot_config("default", ConfigFile);
load(ConfigName, ConfigFile) ->
    load_dot_config(ConfigName, ConfigFile).

%% @private
load_dot_config(ConfigName, ConfigFile) ->
    case file:consult(ConfigFile) of
        {ok, Terms} ->
            %% First, set up the defaults
            case proplists:get_value(default, Terms) of
                undefined -> meh; %% No defaults set, move on.
                Default -> [set(Key, Value) || {Key, Value} <- Default]
            end,
            %% Now, overlay the specific project
            Config = proplists:get_value(list_to_atom(ConfigName), Terms),
            [set(Key, Value) || {Key, Value} <- Config],
            ok;
        {error, Reason} ->
            erlang:error("Failed to parse config file", [ConfigFile, Reason])
 end.

set(Key, Value) ->
    ok = application:set_env(riak_test, Key, Value).


-spec get(rt_max_wait_time | atom()) -> any().
get(rt_max_wait_time) ->
    lager:info("rt_max_wait_time is deprecated. Please use rt_max_receive_wait_time instead."),
    rt_config:get(?RECEIVE_WAIT_TIME_KEY);
get(Key) ->
    case kvc:path(Key, application:get_all_env(?CONFIG_NAMESPACE)) of
        [] ->
            lager:warning("Missing configuration key: ~p", [Key]),
            erlang:error("Missing configuration key", [Key]);
        Value -> Value
    end.

-spec get(rt_max_wait_time | atom(), any()) -> any().
get(rt_max_wait_time, Default) ->
    lager:info("rt_max_wait_time is deprecated. Please use rt_max_receive_wait_time instead."),
    get(?RECEIVE_WAIT_TIME_KEY, Default);
get(Key, Default) ->
    case kvc:path(Key, application:get_all_env(?CONFIG_NAMESPACE)) of
        [] -> Default;
        Value -> Value
    end.

-spec config_or_os_env(atom()) -> term().
config_or_os_env(Config) ->
    OSEnvVar = to_upper(atom_to_list(Config)),
    case {get_os_env(OSEnvVar, undefined), get(Config, undefined)} of
        {undefined, undefined} ->
            MSG = io_lib:format("Neither riak_test.~p nor ENV['~p'] are defined", [Config, OSEnvVar]),
            erlang:error(binary_to_list(iolist_to_binary(MSG)));
        {undefined, V} ->
            lager:info("Found riak_test.~s: ~s", [Config, V]),
            V;
        {V, _} ->
            lager:info("Found ENV[~s]: ~s", [OSEnvVar, V]),
            set(Config, V),
            V
    end.

-spec config_or_os_env(atom(), term()) -> term().
config_or_os_env(Config, Default) ->
    OSEnvVar = to_upper(atom_to_list(Config)),
    case {get_os_env(OSEnvVar, undefined), get(Config, undefined)} of
        {undefined, undefined} -> Default;
        {undefined, V} ->
            lager:info("Found riak_test.~s: ~s", [Config, V]),
            V;
        {V, _} ->
            lager:info("Found ENV[~s]: ~s", [OSEnvVar, V]),
            set(Config, V),
            V
    end.


-spec set_conf(atom(), [{string(), string()}]) -> ok.
set_conf(all, NameValuePairs) ->
    ?HARNESS:set_conf(all, NameValuePairs);
set_conf(Node, NameValuePairs) ->
    rt:stop(Node),
    ?assertEqual(ok, rt:wait_until_unpingable(Node)),
    ?HARNESS:set_conf(Node, NameValuePairs),
    rt:start(Node).

-spec set_advanced_conf(atom(), [{string(), string()}]) -> ok.
set_advanced_conf(all, NameValuePairs) ->
    ?HARNESS:set_advanced_conf(all, NameValuePairs);
set_advanced_conf(Node, NameValuePairs) ->
    rt:stop(Node),
    ?assertEqual(ok, rt:wait_until_unpingable(Node)),
    ?HARNESS:set_advanced_conf(Node, NameValuePairs),
    rt:start(Node).

%% @doc Rewrite the given node's app.config file, overriding the varialbes
%%      in the existing app.config with those in `Config'.
update_app_config(all, Config) ->
    ?HARNESS:update_app_config(all, Config);
update_app_config(Node, Config) ->
    rt:stop(Node),
    ?assertEqual(ok, rt:wait_until_unpingable(Node)),
    ?HARNESS:update_app_config(Node, Config),
    rt:start(Node).

to_upper(S) -> lists:map(fun char_to_upper/1, S).
char_to_upper(C) when C >= $a, C =< $z -> C bxor $\s;
char_to_upper(C) -> C.

%% TODO: Remove after conversion
%% @doc Look up the version by name from the config file
-spec version_to_path(atom()) -> string().
version_to_path(Version) ->
    NewVersion = case Version of
                     current -> default_version;
                     legacy -> legacy_version;
                     previous -> previous_version;
                     _ -> Version
                 end,
    Path = rt_config:get(NewVersion, Version),
    %% If path is stored as an atom, convert to a string
    case is_atom(Path) of
        true -> atom_to_list(Path);
        _ -> Path
    end.

-ifdef(TEST).

clear(Key) ->
    application:unset_env(?CONFIG_NAMESPACE, Key).

get_rt_max_wait_time_test() -> 
    clear(?RECEIVE_WAIT_TIME_KEY),

    ExpectedWaitTime = 10987,
    ok = set(?RECEIVE_WAIT_TIME_KEY, ExpectedWaitTime),
    ?assertEqual(ExpectedWaitTime, rt_config:get(?RECEIVE_WAIT_TIME_KEY)),
    ?assertEqual(ExpectedWaitTime, rt_config:get(rt_max_wait_time)).
        
get_rt_max_wait_time_default_test() ->
    clear(?RECEIVE_WAIT_TIME_KEY),

    DefaultWaitTime = 20564,
    ?assertEqual(DefaultWaitTime, get(?RECEIVE_WAIT_TIME_KEY, DefaultWaitTime)),
    ?assertEqual(DefaultWaitTime, get(rt_max_wait_time, DefaultWaitTime)),
    
    ExpectedWaitTime = 30421,
    ok = set(?RECEIVE_WAIT_TIME_KEY, ExpectedWaitTime),
    ?assertEqual(ExpectedWaitTime, get(?RECEIVE_WAIT_TIME_KEY, DefaultWaitTime)),
    ?assertEqual(ExpectedWaitTime, get(rt_max_wait_time, DefaultWaitTime)).

get_version_path_test() ->
    clear(?DEFAULT_VERSION_KEY),
    clear(?PREVIOUS_VERSION_KEY),
    clear(?LEGACY_VERSION_KEY),

    set(?DEFAULT_VERSION_KEY, atom_to_list(?DEFAULT_VERSION)),
    set(?PREVIOUS_VERSION_KEY, ?PREVIOUS_VERSION),
    set(?LEGACY_VERSION_KEY, ?LEGACY_VERSION),

    ?assertEqual(version_to_path(?DEFAULT_VERSION_KEY), ?DEFAULT_VERSION),
    ?assertEqual(version_to_path(?PREVIOUS_VERSION_KEY), ?PREVIOUS_VERSION),
    ?assertEqual(version_to_path(?LEGACY_VERSION_KEY), ?LEGACY_VERSION).

-endif.
