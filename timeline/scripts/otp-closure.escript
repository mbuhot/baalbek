#!/usr/bin/env escript
%%% Prints the OTP applications an erlang-shipment export must keep, one per
%%% line: the given roots plus everything reachable through their `.app`
%%% files' `applications` keys.
%%%
%%% usage: otp-closure.escript <shipment-dir> <root-app>...
%%%
%%% An application named in a dependency list but absent from the shipment
%%% directory is an OTP built-in (kernel, stdlib, ssl, ...) and is skipped.
%%% An application whose `.app` declares `{modules, []}` aborts the run: a
%%% release boot script is generated from that list, so an empty one loads
%%% none of the application's modules in embedded mode.

%% Elixir's own applications. The shipment vendors copies of these, but the
%% Mix project that consumes this output already supplies the live ones.
-define(PROVIDED_BY_ELIXIR, [elixir, eex, ex_unit, iex, logger, mix]).

main([ShipmentDir | Roots]) when Roots =/= [] ->
    Apps = closure(ShipmentDir, [list_to_atom(R) || R <- Roots], []),
    [io:format("~s~n", [A]) || A <- lists:sort(Apps)];
main(_) ->
    io:format(standard_error, "usage: otp-closure.escript <shipment-dir> <root-app>...~n", []),
    halt(1).

closure(_ShipmentDir, [], Acc) ->
    Acc;
closure(ShipmentDir, [App | Rest], Acc) ->
    case lists:member(App, Acc) orelse lists:member(App, ?PROVIDED_BY_ELIXIR) of
        true ->
            closure(ShipmentDir, Rest, Acc);
        false ->
            Name = atom_to_list(App),
            AppFile = filename:join([ShipmentDir, Name, "ebin", Name ++ ".app"]),
            case file:consult(AppFile) of
                {error, enoent} ->
                    closure(ShipmentDir, Rest, Acc);
                {ok, [{application, App, Keys}]} ->
                    ok = check_modules(App, Keys),
                    Deps = proplists:get_value(applications, Keys, []),
                    closure(ShipmentDir, Deps ++ Rest, [App | Acc]);
                Other ->
                    abort("~s: unreadable .app file (~p)~n", [AppFile, Other])
            end
    end.

check_modules(App, Keys) ->
    case proplists:get_value(modules, Keys, []) of
        [] ->
            abort(
                "~s: .app file declares {modules, []}; a release built from it "
                "would load none of its modules in embedded mode~n",
                [App]
            );
        _ ->
            ok
    end.

abort(Format, Args) ->
    io:format(standard_error, Format, Args),
    halt(1).
