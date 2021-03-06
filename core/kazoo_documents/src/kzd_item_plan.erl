%%%-------------------------------------------------------------------
%%% @copyright (C) 2018, 2600Hz, INC
%%% @doc
%%%
%%% @end
%%% @contributors
%%%-------------------------------------------------------------------
-module(kzd_item_plan).

-export([cumulative_merge_scheme/0
        ,cumulative_merge_sum/2
        ,cumulative_merge_object/2
        ,cumulative_merge_list/2
        ,cumulative_merge_or/2
        ,cumulative_merge_and/2
        ]).
-export([minimum/1, minimum/2
        ,flat_rates/1, flat_rates/2
        ,rates/1, rates/2
        ,rate/1, rate/2
        ,exceptions/1, exceptions/2
        ,should_cascade/1, should_cascade/2
        ,masquerade_as/1, masquerade_as/2
        ,name/1
        ,discounts/1, discounts/2
        ,single_discount/1, single_discount/2
        ,cumulative_discount/1, cumulative_discount/2
        ,activation_charge/1, activation_charge/2
        ,is_enabled/1
        ,keys/1
        ]).

-include("kz_documents.hrl").

-type doc() :: kz_json:object().
-type api_doc() :: kz_term:api_object().
-export_type([doc/0
             ,api_doc/0
             ]).

-define(ACTIVATION_CHARGE, <<"activation_charge">>).
-define(MINIMUM, <<"minimum">>).
-define(FLAT_RATES, <<"flat_rates">>).
-define(RATES, <<"rates">>).
-define(RATE, <<"rate">>).
-define(EXCEPTIONS, <<"exceptions">>).
-define(CASCADE, <<"cascade">>).
-define(MASQUERADE, <<"as">>).
-define(NAME, <<"name">>).
-define(DISCOUNTS, <<"discounts">>).
-define(SINGLE, <<"single">>).
-define(CUMULATIVE, <<"cumulative">>).
-define(MAXIMUM, <<"maximum">>).
-define(ENABLED, <<"enabled">>).

-spec cumulative_merge_scheme() -> kz_json:paths().
cumulative_merge_scheme() ->
    [{?ACTIVATION_CHARGE, fun kz_json:find/2}
    ,{?MINIMUM, fun ?MODULE:cumulative_merge_sum/2}
    ,{?FLAT_RATES, fun kz_json:find/2}
    ,{?RATES, fun ?MODULE:cumulative_merge_object/2}
    ,{?RATE, fun kz_json:find/2}
    ,{?EXCEPTIONS, fun ?MODULE:cumulative_merge_list/2}
    ,{?CASCADE, fun  ?MODULE:cumulative_merge_or/2}
    ,{?MASQUERADE, fun kz_json:find/2}
    ,{?NAME, fun kz_json:find/2}
    ,{[?DISCOUNTS, ?SINGLE, ?RATE], fun kz_json:find/2}
    ,{[?DISCOUNTS, ?SINGLE, ?RATES], fun ?MODULE:cumulative_merge_object/2}
    ,{[?DISCOUNTS, ?CUMULATIVE, ?RATE], fun kz_json:find/2}
    ,{[?DISCOUNTS, ?CUMULATIVE, ?RATES], fun ?MODULE:cumulative_merge_object/2}
    ,{[?DISCOUNTS, ?CUMULATIVE, ?MAXIMUM], fun ?MODULE:cumulative_merge_sum/2}
    ,{?ENABLED, fun ?MODULE:cumulative_merge_and/2}
    ].

-spec cumulative_merge_sum(kz_json:path(), kz_json:objects()) -> non_neg_integer().
cumulative_merge_sum(Key, [JObj|JObjs]) ->
    lists:foldl(fun(J, 'undefined') ->
                        kz_json:get_integer_value(Key, J);
                   (J, Value) ->
                        Value + kz_json:get_integer_value(Key, J, 0)
                end, kz_json:get_integer_value(Key, JObj), JObjs).

-spec cumulative_merge_object(kz_json:path(), kz_json:objects()) -> kz_json:object().
cumulative_merge_object(Key, [JObj|JObjs]) ->
    lists:foldl(fun(J, 'undefined') ->
                        kz_json:get_value(Key, J);
                   (J, Value) ->
                        kz_json:merge(kz_json:get_value(Key, J, kz_json:new()), Value)
                end, kz_json:get_value(Key, JObj), JObjs).

-spec cumulative_merge_list(kz_json:path(), kz_json:objects()) -> list().
cumulative_merge_list(Key, [JObj|JObjs]) ->
    case lists:foldl(fun(J, 'undefined') ->
                             kz_json:get_value(Key, J);
                        (J, Value) ->
                             lists:merge(
                               kz_json:get_list_value(Key, J, [])
                                        ,Value
                              )
                     end, kz_json:get_value(Key, JObj), JObjs)
    of
        'undefined' -> 'undefined';
        List -> sets:to_list(sets:from_list(List))
    end.

-spec cumulative_merge_or(kz_json:path(), kz_json:objects()) -> boolean().
cumulative_merge_or(Key, [JObj|JObjs]) ->
    lists:foldl(fun(J, 'undefined') ->
                        kz_json:get_value(Key, J);
                   (J, Value) ->
                        case kz_json:get_value(Key, J) of
                            'undefined' -> Value;
                            Boolean ->
                                kz_term:is_true(Boolean)
                                    orelse Value
                        end
                end, kz_json:get_value(Key, JObj), JObjs).

-spec cumulative_merge_and(kz_json:path(), kz_json:objects()) -> boolean().
cumulative_merge_and(Key, [JObj|JObjs]) ->
    lists:foldl(fun(J, 'undefined') ->
                        kz_json:get_value(Key, J);
                   (J, Value) ->
                        case kz_json:get_value(Key, J) of
                            'undefined' -> Value;
                            Boolean ->
                                kz_term:is_true(Boolean)
                                    andalso Value
                        end
                end, kz_json:get_value(Key, JObj), JObjs).

-spec keys(doc()) -> kz_json:path().
keys(ItemPlan) ->
    kz_json:get_keys(ItemPlan).

-spec minimum(doc()) -> integer().
minimum(ItemPlan) ->
    minimum(ItemPlan, 0).

-spec minimum(doc(), Default) -> integer() | Default.
minimum(ItemPlan, Default) ->
    kz_json:get_integer_value(?MINIMUM, ItemPlan, Default).

-spec flat_rates(doc()) -> kz_json:object().
flat_rates(ItemPlan) ->
    flat_rates(ItemPlan, kz_json:new()).

-spec flat_rates(doc(), Default) -> kz_json:object() | Default.
flat_rates(ItemPlan, Default) ->
    kz_json:get_json_value(?FLAT_RATES, ItemPlan, Default).

-spec rates(doc()) -> kz_json:object().
rates(ItemPlan) ->
    rates(ItemPlan, kz_json:new()).

-spec rates(doc(), Default) -> kz_json:object() | Default.
rates(ItemPlan, Default) ->
    kz_json:get_json_value(?RATES, ItemPlan, Default).

-spec rate(doc()) -> kz_term:api_float().
rate(ItemPlan) ->
    rate(ItemPlan, 'undefined').

-spec rate(doc(), Default) -> float() | Default.
rate(ItemPlan, Default) ->
    kz_json:get_float_value(?RATE, ItemPlan, Default).

-spec exceptions(doc()) -> kz_term:ne_binaries().
exceptions(ItemPlan) ->
    exceptions(ItemPlan, []).

-spec exceptions(doc(), Default) -> kz_term:ne_binaries() | Default.
exceptions(ItemPlan, Default) ->
    kz_json:get_value(?EXCEPTIONS, ItemPlan, Default).

-spec should_cascade(doc()) -> boolean().
should_cascade(ItemPlan) ->
    should_cascade(ItemPlan, 'false').

-spec should_cascade(doc(), Default) -> boolean() | Default.
should_cascade(ItemPlan, Default) ->
    kz_json:is_true(?CASCADE, ItemPlan, Default).

-spec masquerade_as(doc()) -> kz_term:api_binary().
masquerade_as(ItemPlan) ->
    masquerade_as(ItemPlan, 'undefined').

-spec masquerade_as(doc(), Default) -> kz_term:ne_binary() | Default.
masquerade_as(ItemPlan, Default) ->
    kz_json:get_ne_value(?MASQUERADE, ItemPlan, Default).

-spec name(doc()) -> kz_term:api_binary().
name(ItemPlan) ->
    case kz_json:get_value(?NAME, ItemPlan) of
        'undefined' -> masquerade_as(ItemPlan);
        Name -> Name
    end.

-spec discounts(doc()) -> kz_json:object().
discounts(ItemPlan) ->
    discounts(ItemPlan, kz_json:new()).

-spec discounts(doc(), Default) -> kz_json:object() | Default.
discounts(ItemPlan, Default) ->
    kz_json:get_json_value(?DISCOUNTS, ItemPlan, Default).

-spec single_discount(doc()) -> kz_term:api_object().
single_discount(ItemPlan) ->
    single_discount(ItemPlan, 'undefined').

-spec single_discount(doc(), Default) -> kz_json:object() | Default.
single_discount(ItemPlan, Default) ->
    kz_json:get_json_value([?DISCOUNTS, ?SINGLE], ItemPlan, Default).

-spec cumulative_discount(doc()) -> kz_term:api_object().
cumulative_discount(ItemPlan) ->
    cumulative_discount(ItemPlan, 'undefined').

-spec cumulative_discount(doc(), Default) -> kz_json:object() | Default.
cumulative_discount(ItemPlan, Default) ->
    kz_json:get_json_value([?DISCOUNTS, ?CUMULATIVE], ItemPlan, Default).

-spec activation_charge(doc()) -> float().
activation_charge(ItemPlan) ->
    activation_charge(ItemPlan, 0.0).

-spec activation_charge(doc(), Default) -> float() | Default.
activation_charge(ItemPlan, Default) ->
    kz_json:get_float_value(?ACTIVATION_CHARGE, ItemPlan, Default).

-spec is_enabled(doc()) -> boolean().
is_enabled(ItemPlan) ->
    kz_json:is_true(?ENABLED, ItemPlan).
