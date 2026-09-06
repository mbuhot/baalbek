%% Erlang FFI for timeline: OS environment lookups, which Gleam's stdlib
%% does not cover.
-module(timeline_ffi).

-export([getenv/2]).

-spec getenv(binary(), binary()) -> binary().
getenv(Name, Default) ->
    case os:getenv(binary_to_list(Name)) of
        false -> Default;
        "" -> Default;
        Value -> list_to_binary(Value)
    end.
