%%%-------------------------------------------------------------------
%%% @copyright (C) 2011-2018, 2600Hz INC
%%% @doc
%%%
%%% storage
%%%
%%% @end
%%% @contributors:
%%%-------------------------------------------------------------------
-module(cb_storage).

-export([init/0
        ,authorize/1, authorize/2, authorize/3
        ,allowed_methods/0, allowed_methods/1, allowed_methods/2
        ,resource_exists/0, resource_exists/1, resource_exists/2
        ,validate/1, validate/2, validate/3
        ,put/1, put/2
        ,post/1, post/3
        ,patch/1, patch/3
        ,delete/1, delete/3
        ]).

-ifdef(TEST).
-export([maybe_check_storage_settings/2]).
-endif.

-include("crossbar.hrl").

-define(CB_ACCOUNT_LIST, <<"storage/plans_by_account">>).
-define(CB_SYSTEM_LIST, <<"storage/system_plans">>).

-define(SYSTEM_DATAPLAN, <<"system">>).

-define(PLANS_TOKEN, <<"plans">>).

-define(STORAGE_TYPES, [<<"storage">>, <<"storage_plan">>]).
-define(STORAGE_CHECK_OPTION, {?OPTION_EXPECTED_TYPE, ?STORAGE_TYPES}).
-define(STORAGE_CHECK_OPTIONS, [?STORAGE_CHECK_OPTION]).

-type scope() :: 'system'
               | 'system_plans'
               | {'system_plan', kz_term:ne_binary()}
               | {'user', kz_term:ne_binary(), kz_term:ne_binary()}
               | {'account', kz_term:ne_binary()}
               | {'reseller_plans', kz_term:ne_binary()}
               | {'reseller_plan', kz_term:ne_binary(), kz_term:ne_binary()}
               | 'invalid'.

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
    _ = crossbar_bindings:bind(<<"*.authorize">>, ?MODULE, 'authorize'),
    _ = crossbar_bindings:bind(<<"*.allowed_methods.storage">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.storage">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.validate.storage">>, ?MODULE, 'validate'),
    _ = crossbar_bindings:bind(<<"*.execute.get.storage">>, ?MODULE, 'get'),
    _ = crossbar_bindings:bind(<<"*.execute.put.storage">>, ?MODULE, 'put'),
    _ = crossbar_bindings:bind(<<"*.execute.post.storage">>, ?MODULE, 'post'),
    _ = crossbar_bindings:bind(<<"*.execute.patch.storage">>, ?MODULE, 'patch'),
    _ = crossbar_bindings:bind(<<"*.execute.delete.storage">>, ?MODULE, 'delete').


%%--------------------------------------------------------------------
%% @public
%% @doc
%% Authorizes the incoming request, returning true if the requestor is
%% allowed to access the resource, or false if not.
%% @end
%%--------------------------------------------------------------------
-spec authorize(cb_context:context()) -> boolean().
authorize(Context) ->
    do_authorize(set_scope(Context)).

-spec authorize(cb_context:context(), path_token()) -> boolean().
authorize(Context, ?PLANS_TOKEN) ->
    do_authorize(set_scope(Context)).

-spec authorize(cb_context:context(), path_token(), path_token()) -> boolean().
authorize(Context, ?PLANS_TOKEN, _PlanId) ->
    do_authorize(set_scope(Context)).

-spec do_authorize(cb_context:context()) -> boolean().
do_authorize(Context) ->
    do_authorize(Context, scope(Context)).

-spec do_authorize(cb_context:context(), scope()) -> boolean().
do_authorize(_Context, 'invalid') -> 'false';
do_authorize(Context, 'system') -> cb_context:is_superduper_admin(Context);
do_authorize(Context, 'system_plans') -> cb_context:is_superduper_admin(Context);
do_authorize(Context, {'system_plan', _PlanId}) -> cb_context:is_superduper_admin(Context);
do_authorize(Context, {'reseller_plans', _AccountId}) ->
    kzd_accounts:is_reseller(cb_context:account_doc(Context));
do_authorize(Context, {'reseller_plan', _PlanId, _AccountId}) ->
    kzd_accounts:is_reseller(cb_context:account_doc(Context));
do_authorize(Context, {'account', AccountId}) ->
    cb_context:is_superduper_admin(Context)
        orelse kz_services:get_reseller_id(AccountId) =:= cb_context:auth_account_id(Context)
        orelse AccountId =:= cb_context:auth_account_id(Context);
do_authorize(Context, {'user', UserId, AccountId}) ->
    cb_context:is_superduper_admin(Context)
        orelse kz_services:get_reseller_id(AccountId) =:= cb_context:auth_account_id(Context)
        orelse ( (AccountId =:= cb_context:auth_account_id(Context)
                  andalso cb_context:is_account_admin(Context)
                 )
                 orelse
                   (AccountId =:= cb_context:auth_account_id(Context)
                    andalso UserId =:= cb_context:auth_user_id(Context)
                   )
               ).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%--------------------------------------------------------------------
-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_GET, ?HTTP_PUT, ?HTTP_POST, ?HTTP_PATCH, ?HTTP_DELETE].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(?PLANS_TOKEN) ->
    [?HTTP_GET, ?HTTP_PUT].

-spec allowed_methods(path_token(), path_token()) -> http_methods().
allowed_methods(?PLANS_TOKEN, _StoragePlanId) ->
    [?HTTP_GET, ?HTTP_POST, ?HTTP_PATCH, ?HTTP_DELETE].

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Does the path point to a valid resource
%% So /storage => []
%%    /storage/foo => [<<"foo">>]
%%    /storage/foo/bar => [<<"foo">>, <<"bar">>]
%% @end
%%--------------------------------------------------------------------
-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(?PLANS_TOKEN) -> 'true'.

-spec resource_exists(path_token(), path_token()) -> 'true'.
resource_exists(?PLANS_TOKEN, _PlanId) -> 'true'.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Check the request (request body, query string params, path tokens, etc)
%% and load necessary information.
%% /storage mights load a list of storage objects
%% /storage/123 might load the storage object 123
%% Generally, use crossbar_doc to manipulate the cb_context{} record
%% @end
%%--------------------------------------------------------------------
-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    ReqVerb = cb_context:req_verb(Context),
    Context1 = validate_storage(set_scope(Context), ReqVerb),
    maybe_check_storage_settings(Context1, ReqVerb).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, ?PLANS_TOKEN) ->
    validate_storage_plans(set_scope(Context), cb_context:req_verb(Context)).

-spec validate(cb_context:context(), path_token(), path_token()) -> cb_context:context().
validate(Context, ?PLANS_TOKEN, PlanId) ->
    validate_storage_plan(set_scope(Context), PlanId, cb_context:req_verb(Context)).


-spec validate_storage(cb_context:context(), http_method()) -> cb_context:context().
validate_storage(Context, ?HTTP_GET) ->
    read(Context);
validate_storage(Context, ?HTTP_PUT) ->
    create(Context);
validate_storage(Context, ?HTTP_POST) ->
    update(Context);
validate_storage(Context, ?HTTP_PATCH) ->
    patch_update(Context);
validate_storage(Context, ?HTTP_DELETE) ->
    read(Context).

-spec validate_storage_plans(cb_context:context(), http_method()) -> cb_context:context().
validate_storage_plans(Context, ?HTTP_GET) ->
    summary(Context);
validate_storage_plans(Context, ?HTTP_PUT) ->
    create(Context).

-spec validate_storage_plan(cb_context:context(), kz_term:ne_binary(), http_method()) -> cb_context:context().
validate_storage_plan(Context, PlanId, ?HTTP_GET) ->
    read(Context, PlanId);
validate_storage_plan(Context, PlanId, ?HTTP_POST) ->
    update(Context, PlanId);
validate_storage_plan(Context, PlanId, ?HTTP_PATCH) ->
    patch_update(Context, PlanId);
validate_storage_plan(Context, PlanId, ?HTTP_DELETE) ->
    read(Context, PlanId).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% If the HTTP verb is PUT, execute the actual action, usually a db save.
%% @end
%%--------------------------------------------------------------------
-spec put(cb_context:context()) -> cb_context:context().
put(Context) ->
    crossbar_doc:save(Context).

-spec put(cb_context:context(), path_token()) -> cb_context:context().
put(Context, ?PLANS_TOKEN) ->
    crossbar_doc:save(Context).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% If the HTTP verb is POST, execute the actual action, usually a db save
%% (after a merge perhaps).
%% @end
%%--------------------------------------------------------------------
-spec post(cb_context:context()) -> cb_context:context().
post(Context) ->
    crossbar_doc:save(Context).

-spec post(cb_context:context(), path_token(), path_token()) -> cb_context:context().
post(Context, ?PLANS_TOKEN, _PlanId) ->
    crossbar_doc:save(Context).

-spec patch(cb_context:context()) -> cb_context:context().
patch(Context) ->
    post(Context).

-spec patch(cb_context:context(), path_token(), path_token()) -> cb_context:context().
patch(Context, ?PLANS_TOKEN, PlanId) ->
    post(Context, ?PLANS_TOKEN, PlanId).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% If the HTTP verb is DELETE, execute the actual action, usually a db delete
%% @end
%%--------------------------------------------------------------------
-spec delete(cb_context:context()) -> cb_context:context().
delete(Context) ->
    crossbar_doc:delete(Context).

-spec delete(cb_context:context(), path_token(), path_token()) -> cb_context:context().
delete(Context, ?PLANS_TOKEN, _PlanId) ->
    crossbar_doc:delete(Context).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Create a new instance with the data provided, if it is valid
%% @end
%%--------------------------------------------------------------------
-spec create(cb_context:context()) -> cb_context:context().
create(Context) ->
    OnSuccess = fun(C) -> on_successful_validation(doc_id(Context), C) end,
    cb_context:validate_request_data(<<"storage">>, Context, OnSuccess).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Load an instance from the database
%% @end
%%--------------------------------------------------------------------
-spec read(cb_context:context()) -> cb_context:context().
read(Context) ->
    crossbar_doc:load(doc_id(Context), Context, ?TYPE_CHECK_OPTION(<<"storage">>)).

-spec read(cb_context:context(), path_token()) -> cb_context:context().
read(Context, PlanId) ->
    crossbar_doc:load(PlanId, Context, ?TYPE_CHECK_OPTION(<<"storage">>)).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Update an existing menu document with the data provided, if it is
%% valid
%% @end
%%--------------------------------------------------------------------
-spec update(cb_context:context()) -> cb_context:context().
update(Context) ->
    OnSuccess = fun(C) -> on_successful_validation(doc_id(Context), C) end,
    cb_context:validate_request_data(<<"storage">>, Context, OnSuccess).

-spec patch_update(cb_context:context()) -> cb_context:context().
patch_update(Context) ->
    VFun = fun(_Id, LoadedContext) -> update(LoadedContext) end,
    crossbar_doc:patch_and_validate(doc_id(Context), Context, VFun).

-spec update(cb_context:context(), path_token()) -> cb_context:context().
update(Context, PlanId) ->
    OnSuccess = fun(C) -> on_successful_validation(PlanId, C) end,
    cb_context:validate_request_data(<<"storage">>, Context, OnSuccess).

-spec patch_update(cb_context:context(), path_token()) -> cb_context:context().
patch_update(Context, PlanId) ->
    VFun = fun(Id, LoadedContext) -> update(LoadedContext, Id) end,
    crossbar_doc:patch_and_validate(PlanId, Context, VFun).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Attempt to load a summarized listing of all instances of this
%% resource.
%% @end
%%--------------------------------------------------------------------
-spec summary(cb_context:context()) -> cb_context:context().
summary(Context) ->
    summary(Context, scope(Context)).

-spec summary(cb_context:context(), scope()) -> cb_context:context().
summary(Context, 'system_plans') ->
    crossbar_doc:load_view(?CB_SYSTEM_LIST, ['include_docs'], Context, fun normalize_view_results/2);

summary(Context, {'reseller_plans', AccountId}) ->
    Options = ['include_docs'
              ,{'startkey', [AccountId]}
              ,{'endkey', [AccountId, kz_json:new()]}
              ],
    crossbar_doc:load_view(?CB_ACCOUNT_LIST, Options, Context, fun normalize_view_results/2).

%%--------------------------------------------------------------------
%% @private
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec on_successful_validation(kz_term:api_binary(), cb_context:context()) -> cb_context:context().
on_successful_validation(Id, Context) ->
    on_successful_validation(Id, cb_context:req_verb(Context), Context).

-spec on_successful_validation(kz_term:api_binary(), http_method(), cb_context:context()) -> cb_context:context().
on_successful_validation('undefined', ?HTTP_PUT, Context) ->
    IsSystemPlan = scope(Context) =:= 'system_plans',
    JObj = cb_context:doc(Context),
    Routines = [fun(Doc) -> kz_doc:set_type(Doc, <<"storage_plan">>) end
               ,fun(Doc) -> kz_json:set_value(<<"pvt_system_plan">>, IsSystemPlan, Doc) end
               ],
    cb_context:set_doc(Context, kz_json:exec(Routines, JObj));
on_successful_validation(Id, ?HTTP_PUT, Context) ->
    JObj = cb_context:doc(Context),
    Routines = [fun(Doc) -> kz_doc:set_type(Doc, <<"storage">>) end
               ,fun(Doc) -> kz_doc:set_id(Doc, Id) end
               ],
    cb_context:set_doc(Context, kz_json:exec(Routines, JObj));
on_successful_validation(Id, ?HTTP_POST, Context) ->
    crossbar_doc:load_merge(Id, Context, ?STORAGE_CHECK_OPTIONS);
on_successful_validation(Id, ?HTTP_PATCH, Context) ->
    crossbar_doc:load_merge(Id, Context, ?STORAGE_CHECK_OPTIONS).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Normalizes the results of a view
%% @end
%%--------------------------------------------------------------------
-spec normalize_view_results(kz_json:object(), kz_json:objects()) -> kz_json:objects().
normalize_view_results(JObj, Acc) ->
    [kz_json:get_value(<<"doc">>, JObj)|Acc].

-spec scope(cb_context:context()) -> scope().
scope(Context) ->
    cb_context:fetch(Context, 'scope').

-spec set_scope(cb_context:context()) -> cb_context:context().
set_scope(Context) ->
    Setters = [{fun cb_context:store/3, 'ensure_valid_schema', 'true'}
              ,{fun cb_context:set_account_db/2, ?KZ_DATA_DB}
              ],
    set_scope(cb_context:setters(Context, Setters), cb_context:req_nouns(Context)).

-spec set_scope(cb_context:context(), req_nouns()) -> cb_context:context().
set_scope(Context, [{<<"storage">>, []}]) ->
    cb_context:store(Context, 'scope', 'system');
set_scope(Context, [{<<"storage">>, [?PLANS_TOKEN]}]) ->
    cb_context:store(Context, 'scope', 'system_plans');
set_scope(Context, [{<<"storage">>, [?PLANS_TOKEN, PlanId]}]) ->
    cb_context:store(Context, 'scope', {'system_plan', PlanId});
set_scope(Context, [{<<"storage">>, []}
                   ,{<<"accounts">>, [AccountId]}
                   ]) ->
    cb_context:store(Context, 'scope', {'account', AccountId});
set_scope(Context, [{<<"storage">>, [?PLANS_TOKEN]}
                   ,{<<"accounts">>, [AccountId]}
                   ]) ->
    cb_context:store(Context, 'scope', {'reseller_plans', AccountId});
set_scope(Context, [{<<"storage">>, [?PLANS_TOKEN, PlanId]}
                   ,{<<"accounts">>, [AccountId]}
                   ]) ->
    cb_context:store(Context, 'scope', {'reseller_plan', PlanId, AccountId});
set_scope(Context, [{<<"storage">>, []}
                   ,{<<"users">>, [UserId]}
                   ,{<<"accounts">>, [AccountId]}
                   ]) ->
    cb_context:store(Context, 'scope', {'user', UserId, AccountId});
set_scope(Context, _Nouns) ->
    cb_context:store(Context, 'scope', 'invalid').

-spec doc_id(cb_context:context() | scope()) -> kz_term:api_binary().
doc_id('system') -> <<"system">>;
doc_id('system_plans') -> 'undefined';
doc_id({'system_plan', PlanId}) -> PlanId;
doc_id({'account', AccountId}) -> AccountId;
doc_id({'user', UserId, _AccountId}) -> UserId;
doc_id({'reseller_plans', _AccountId}) -> 'undefined';
doc_id({'reseller_plan', PlanId, _AccountId}) -> PlanId;
doc_id(Context) -> doc_id(scope(Context)).

-spec maybe_check_storage_settings(cb_context:context(), kz_term:ne_binary()) ->
                                          cb_context:context().
maybe_check_storage_settings(Context, ReqVerb) when ReqVerb =:= ?HTTP_PUT
                                                    orelse ReqVerb =:= ?HTTP_POST
                                                    orelse ReqVerb =:= ?HTTP_PATCH ->
    case cb_context:resp_status(Context) of
        'success' ->
            lager:debug("validating storage settings"),
            Attachments = kz_json:get_json_value(<<"attachments">>, cb_context:doc(Context)),
            validate_attachments_settings(Attachments, Context);
        _ ->
            Context
    end;
maybe_check_storage_settings(Context, _ReqVerb) ->
    Context.

-spec validate_attachments_settings(kz_json:object()
                                   ,cb_context:context()
                                   ) -> cb_context:context().
validate_attachments_settings(Attachments, Context) ->
    kz_json:foldl(fun validate_attachment_settings_fold/3, Context, Attachments).

-spec validate_attachment_settings_fold(kz_term:ne_binary()
                                       ,kz_json:object()
                                       ,cb_context:context()
                                       ) -> cb_context:context().
validate_attachment_settings_fold(AttId, Att, ContextAcc) ->
    %% Files content will differ at least on this value and also this `Random'
    %% value is used to make sure we always send unique attachment names when
    %% testing storage settings.
    Random = kz_binary:rand_hex(16),
    Content = <<"some random content: ", Random/binary>>,
    AName = <<Random/binary, "_test_credentials_file.txt">>,
    DbName = cb_context:account_db(ContextAcc),
    DocId = doc_id(ContextAcc),
    Handler = kz_json:get_ne_binary_value(<<"handler">>, Att),
    Settings = kz_json:get_json_value(<<"settings">>, Att),
    AttHandler = kz_term:to_atom(<<"kz_att_", Handler/binary>>, 'true'),
    AttSettings = kz_maps:keys_to_atoms(kz_json:to_map(Settings)),
    Opts = [{'plan_override', #{'att_handler' => {AttHandler, AttSettings}
                               ,'att_post_handler' => 'external'
                               }}],
    %% Check the storage settings have permissions to create files
    case kz_datamgr:put_attachment(DbName, DocId, AName, Content, Opts) of
        {'ok', _CreatedDoc, _CreatedProps} ->
            %% Check the storage settings have permissions to read files
            case kz_datamgr:fetch_attachment(DbName, DocId, AName, Opts) of
                {'ok', _Content} ->
                    ContextAcc;
                {'error', Error} ->
                    add_datamgr_error(AttId, Error, ContextAcc);
                AttachmentError ->
                    add_att_settings_validation_error(AttId, AttachmentError, ContextAcc)
            end;
        {'error', Error} ->
            add_datamgr_error(AttId, Error, ContextAcc);
        AttachmentError ->
            add_att_settings_validation_error(AttId, AttachmentError, ContextAcc)
    end.

-spec add_datamgr_error(kz_term:ne_binary(), kz_datamgr:data_errors(), cb_context:context()) ->
                               cb_context:context().
add_datamgr_error(AttId, Error, Context) ->
    crossbar_doc:handle_datamgr_errors(Error, AttId, Context).

-spec add_att_settings_validation_error(kz_term:ne_binary()
                                       ,gen_attachment:error_response()
                                       ,cb_context:context()
                                       ) -> cb_context:context().
add_att_settings_validation_error(AttId, ErrorResponse, Context) ->
    ErrorCode = gen_attachment:error_code(ErrorResponse),
    ErrorBody = gen_attachment:error_body(ErrorResponse),
    EmptyJObj = kz_json:new(),
    %% Some attachment handlers return a bitstring as the value for `ErrorBody` variable,
    %% some other return an encoded JSON object which is also a binary value but
    %% if you pass a bitstring to kz_json:decode/1 you will get an empty object.
    NewErrorBody = case kz_json:decode(ErrorBody) of
                       EmptyJObj -> ErrorBody;
                       DecodedErrorBody -> DecodedErrorBody
                   end,
    Error = [{<<"error_code">>, ErrorCode}, {<<"error_body">>, NewErrorBody}],
    Reason = kz_json:insert_values(Error, kz_json:new()),
    cb_context:add_validation_error([<<"attachments">>, AttId]
                                   ,<<"invalid">>
                                   ,Reason
                                   ,Context
                                   ).
