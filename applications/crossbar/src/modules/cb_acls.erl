%%%-------------------------------------------------------------------
%%% @copyright (C) 2011-2018, 2600Hz
%%% @doc
%%%
%%% ACLs from 7 to 77
%%%
%%% @end
%%% Contributors: Karl Anderson
%%%               James Aimonetti
%%%               Edouard Swiac
%%%-------------------------------------------------------------------
-module(cb_acls).

-export([init/0
        ,allowed_methods/0
        ,resource_exists/0
        ,validate/1
        ]).

-include("crossbar.hrl").
-define(ECALLMGR, <<"ecallmgr">>).
-define(ECALLMGR_ACLS, <<"acls">>).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Initializes the bindings this module will respond to.
%% @end
%%--------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.allowed_methods.acls">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.acls">>, ?MODULE, 'resource_exists'),
    crossbar_bindings:bind(<<"*.validate.acls">>, ?MODULE, 'validate').

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%--------------------------------------------------------------------
-spec allowed_methods() -> http_methods().
allowed_methods() -> [?HTTP_GET].

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Does the path point to a valid resource
%% So /acls => []
%%    /acls/foo => [<<"foo">>]
%%    /acls/foo/bar => [<<"foo">>, <<"bar">>]
%% @end
%%--------------------------------------------------------------------
-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Check the request (request body, query string params, path tokens, etc)
%% and load necessary information.
%% /acls mights load a list of skel objects
%% /acls/123 might load the skel object 123
%% @end
%%--------------------------------------------------------------------
-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    validate_summary(Context, cb_context:req_verb(Context)).

-spec validate_summary(cb_context:context(), http_method()) -> cb_context:context().
validate_summary(Context, ?HTTP_GET) ->
    summary(Context).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Attempt to load a summarized listing of all instances of this
%% resource.
%% @end
%%--------------------------------------------------------------------
-spec summary(cb_context:context()) -> cb_context:context().
summary(Context) ->
    Req = [{<<"Category">>, ?ECALLMGR}
          ,{<<"Key">>, ?ECALLMGR_ACLS}
          ,{<<"Default">>, kz_json:new()}
          ,{<<"Node">>, kz_term:to_binary(node())}
          ,{<<"Msg-ID">>, kz_binary:rand_hex(16)}
           | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
          ],
    lager:debug("looking up acls from sysconf", []),
    ReqResp = kapps_util:amqp_pool_request(Req
                                          ,fun kapi_sysconf:publish_get_req/1
                                          ,fun kapi_sysconf:get_resp_v/1
                                          ,2 * ?MILLISECONDS_IN_SECOND
                                          ),
    case ReqResp of
        {'error', _R} ->
            lager:debug("unable to get acls from sysconf: ~p", [_R]),
            cb_context:add_system_error('datastore_fault', Context);
        {'ok', JObj} ->
            ACLs = kz_json:get_value(<<"Value">>, JObj, kz_json:new()),
            cb_context:setters(Context, [{fun cb_context:set_resp_data/2, ACLs}
                                        ,{fun cb_context:set_resp_status/2, 'success'}
                                        ])
    end.
