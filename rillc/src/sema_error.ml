(*
 * Copyright yutopp 2015 - .
 *
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE_1_0.txt or copy at
 * http://www.boost.org/LICENSE_1_0.txt)
 *)

open Batteries
open Sema_definitions
open Sema_context

exception Instantiation_failed of string
exception Template_type_mismatch

exception Normal_error of error_msg_t
exception Fatal_error of error_msg_t

let error err =
  raise (Normal_error err)

let error_msg msg =
  raise (Normal_error (Error_msg.Msg msg))

let fatal_error err =
  raise (Fatal_error err)

let fatal_error_msg msg =
  raise (Fatal_error (Error_msg.Msg msg))

let show_env env =
  let open Error_msg in

  let env_loc = env.Env.loc in
  match Env.get_env_record env with
  | Env.Module (lt, r) ->
     Printf.sprintf "  module   : %s (%s)"
                    r.Env.mod_name
                    (Loc.to_string env_loc)
  | Env.Function (lt, r) ->
     let name = Id_string.to_string r.Env.fn_name in
     let f pk =
       match pk with
       | Env.FnParamKindType ty -> Type.to_string ty
     in
     let params_s = r.Env.fn_param_kinds |> List.map f |> String.join ", " in
     let ret_ty_s = r.Env.fn_return_type |> Type.to_string in
     Printf.sprintf "  function : %s(%s): %s (%s)"
                    name
                    params_s
                    ret_ty_s
                    (Loc.to_string env_loc)
  | Env.Class (lt, r) ->
     let name = Id_string.to_string r.Env.cls_name in
     Printf.sprintf "  class    : %s (%s)"
                    name
                    (Loc.to_string env_loc)

  | Env.Variable r ->
     let name = Id_string.to_string r.Env.var_name in
     Printf.sprintf "  variable    : %s (%s)"
                    name
                    (Loc.to_string env_loc)

  | Env.Scope _ ->
     Printf.sprintf "Scope"

  | Env.Root _ -> ""
  | Env.MetaVariable _ -> ""
  | Env.MultiSet _ -> ""
  | _ -> failwith "[ICE] unknown env"

let string_of_loc_region loc =
  match loc with
  | Some l ->
     assert (l.Loc.pos_begin_cnum >= 0);
     assert (l.Loc.pos_end_cnum >= 0);
     assert (l.Loc.pos_end_cnum > l.Loc.pos_begin_cnum);

     let lines =
       Batteries.File.with_file_in l.Loc.pos_fname
                                   (fun input ->
                                     let lines =
                                       input
                                       |> IO.to_input_channel
                                       |> input_lines
                                     in

                                     Enum.drop (l.Loc.pos_begin_lnum-1) lines;
                                     let rng =
                                       Enum.take (l.Loc.pos_end_lnum - (l.Loc.pos_begin_lnum - 1)) lines
                                     in

                                     rng |> List.of_enum
                                   )
     in
     let range = lines |> String.join "\n" in
     if l.Loc.pos_begin_lnum == l.Loc.pos_end_lnum then
       String.sub range l.Loc.pos_begin_bol (l.Loc.pos_end_bol - l.Loc.pos_begin_bol)
     else
       (* TODO: implement *)
       range
  | None -> "<unknown>"

let rec print ?(loc=None) err =
  let open Error_msg in

  match err with
  | DifferentArgNum (params_num, args_num) ->
     Printf.printf "%s:\nError: requires %d but given %d\n"
                   (Loc.to_string loc) params_num args_num

  | ConvErr (m, f_env) ->
     Printf.printf "Type mismatch to call %s:\n"
                   (show_env f_env);
     let p k (trg_ty, (src_ty, src_loc), level) =
       Printf.printf "  %dth arg\n" k;
       let _ = match level with
         | Function.MatchLevel.NoMatch ->
            Printf.printf "    expr   :  %s (%s)\n"
                          (string_of_loc_region src_loc) (Loc.to_string src_loc);
            Printf.printf "    found  :  %s\n" (Type.to_string src_ty);
            Printf.printf "    expect :  %s\n" (Type.to_string trg_ty);
         | _ ->
            failwith "[ERR] not supported"
       in
       ()
     in
     ArgLocMap.iter p m

  | NoMatch (errs, loc) ->
     Printf.printf "%s:\nError: There is no matched function\n"
                   (Loc.to_string loc);
     List.iter (fun err -> print err; Printf.printf "\n") errs

  | MemberNotFound (env, history, loc) ->
     let env_name = Id_string.to_string (Env.get_name env) in

     Printf.printf "%s:\nError: member \"%s\" is not found in %s\n"
                   (Loc.to_string loc)
                   (string_of_loc_region loc)
                   env_name;
     Printf.printf "Searched scopes are...\n";
     List.iter (fun env -> show_env env |> Printf.printf "%s\n") history

  | PackageNotFound (full_module_name, hist) ->
     Printf.printf "Error: module \"%s\" is not found.\n" full_module_name;
     hist |> List.iter
               (fun (package_name, dirs) ->
                 Printf.printf " \"%s\" is not found in\n" package_name;
                 dirs |> List.iter
                           (fun d ->
                             Printf.printf "  -> %s\n" d;
                           );
                 ()
               )

  | Ambiguous (_, f_envs, loc) ->
     Printf.printf "%s:\nError: Ambiguous\n"
                   (Loc.to_string loc);
     List.iter (fun env ->
                Printf.printf "%s\n" (show_env env))
               f_envs

  | MultiSymbol (env, loc) ->
     Printf.printf "%s:\nError: Symbol is already defined\n"
                   (Loc.to_string loc);
     Printf.printf "%s" (show_env env);

  | Msg msg ->
     Printf.printf "\n------------------\nError:\n %s\n\n-------------------\n" msg

  | TmpError (msg, env) ->
     Printf.printf "\n------------------\nError:\n %s\n\n-------------------\n" msg;
     let history =
       let rec f oe xs =
         match oe with
         | Some e -> f (Env.get_parent_env_opt e) (e :: xs)
         | None -> xs
       in
       f (Some env) [] |> List.rev
     in
     List.iter (fun env -> show_env env |> Printf.printf "%s\n") history

let process_error err ctx =
  Printf.printf "\n===============================\n";
  print err;
  store_error_message "" ctx;
  Printf.printf "\n===============================\n";
  ()
