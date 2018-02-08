-module(gen_attachment).

-include("kz_att.hrl").

-type settings()         :: kz_data:connection().
-type db_name()          :: kz_term:ne_binary().
-type doc_id()           :: kz_term:ne_binary().
-type att_name()         :: kz_term:ne_binary().
-type contents()         :: kz_term:ne_binary().
-type options()          :: kz_data:options().
-type handler_props()    :: kz_data:connection().

-type put_response()     :: {'ok', [{atom(), [{binary(), binary() | kz_json:object()}]}]} |
                            kz_datamgr:data_error() | 
                            kz_att_extended_error:error().

-type fetch_response()   :: {'ok', iodata()} | 
                            kz_datamgr:data_error() |
                            kz_att_extended_error:error().

-export_type([settings/0
             ,db_name/0
             ,doc_id/0
             ,att_name/0
             ,contents/0
             ,options/0
             ,handler_props/0
             ,put_response/0
             ,fetch_response/0
             ]).

%% Note: Some functions have the `kz_datamgr:data_error()' type in its spec but it is not
%%       being used, it is just to avoid dialyzer complaints because since `cb_storage'
%%       mod is using `kazoo_attachments' app through `kz_datamgr' mod it (cb_storage) can
%%       not get only opaque `error_response()' errors but also `data_error()' from
%%       kz_datamgr and when you call ?MODULE:[error_code/1, error_body/1, is_error_response/1]
%%       you might actually be sending a `data_error()' instead of a `error_response()' value.

%% =======================================================================================
%% Callbacks
%% =======================================================================================
-callback put_attachment(settings()
                        ,db_name()
                        ,doc_id()
                        ,att_name()
                        ,contents()
                        ,options()
                        ) -> put_response().

-callback fetch_attachment(handler_props()
                          ,db_name()
                          ,doc_id()
                          ,att_name()
                          ) -> fetch_response().
