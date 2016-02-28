(*
 * Copyright yutopp 2015 - .
 *
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE_1_0.txt or copy at
 * http://www.boost.org/LICENSE_1_0.txt)
 *)

open Batteries
open Type_sets
open Sema_predef
open Sema_forward_ref

let rec construct_env node parent_env ctx opt_chain_attr =
  match node with
  | TAst.Module (inner, pkg_names, mod_name, base_dir, Some env) ->
     begin
       construct_env inner env ctx opt_chain_attr
     end

  | TAst.StatementList (nodes) ->
     let f n = construct_env n parent_env ctx opt_chain_attr in
     let tagged_nodes = nodes |> List.map f in
     TAst.StatementList tagged_nodes

  | TAst.ExprStmt (TAst.PrevPassNode e) ->
     let (node, ty) = analyze_expr ~making_placeholder:false
                                   e parent_env ctx opt_chain_attr in
     TAst.ExprStmt node

  | TAst.ScopeStmt (block) ->
     begin
       let scope_env =
         Env.create_env parent_env (Env.Scope (Env.empty_lookup_table ()))
       in
       let nblock = analyze_inner block scope_env ctx opt_chain_attr in
       let node = TAst.ScopeStmt (nblock) in
       node
     end

  | TAst.FunctionDefStmt (
        name, params_node, opt_ret_type, body, opt_attr, Some env
      ) ->
     if Env.is_checked env then Env.get_rel_ast env
     else begin
       (* TODO: check duplicate *)
       let name_s = Nodes.string_of_id_string name in
       Printf.printf "function %s - unchecked\n" name_s;
       check_env env;

       (* check parameters *)
       let (params, param_types, param_venvs) =
         prepare_params env node params_node ctx opt_attr in

       (* infer return type *)
       (* TODO: implement *)
       let return_type = get_builtin_void_type ctx in

       (* body *)
       let nbody = analyze_inner body env ctx opt_attr in

       Printf.printf "function %s - complete\n" name_s;
       let node = TAst.GenericFuncDef (Some nbody, Some env) in

       (* update record *)
       let detail_r = {
         Env.fn_n_param_envs = param_venvs;
       } in

       complete_function_env env node
                             name_s param_types return_type
                             (Env.FnRecordNormal (Env.FnKindFree, detail_r))
                             ctx;
       node
     end

  | TAst.ExternFunctionDefStmt (
        name, params_node, ret_type, extern_fname, opt_attr, Some env) ->
     if Env.is_checked env then Env.get_rel_ast env
     else begin
       (* TODO: check duplicate *)
       let name_s = Nodes.string_of_id_string name in
       Printf.printf "extern function %s - unchecked\n" name_s;
       check_env env;

       (* check parameters *)
       let (params, param_types, _) =
         prepare_params env node params_node ctx opt_attr in

       (* determine return type *)
       let var_attr = {
         Type_attr.ta_ref_val = Type_attr.Val;
         Type_attr.ta_mut = Type_attr.Mutable;
       } in
       let return_type =
         resolve_type var_attr
                      (extract_prev_pass_node ret_type)
                      parent_env ctx opt_attr
       in

       (* TODO: fix *)
       let is_builtin = match opt_attr with
           Some tbl -> Hashtbl.mem tbl "builtin"
         | None -> false
       in

       (* body *)
       Printf.printf "extern function %s - complete (builtin=%b)\n" name_s is_builtin;
       let node = TAst.GenericFuncDef (None, Some env) in

       (* update record *)
       let record = if is_builtin then
                      Env.FnRecordBuiltin (Env.FnDefUserDefined,
                                           Env.FnKindFree,
                                           extern_fname)
                    else
                      Env.FnRecordExternal (Env.FnDefUserDefined,
                                            Env.FnKindFree,
                                            extern_fname)
       in
       complete_function_env env node
                             name_s param_types return_type
                             record
                             ctx;

       node
     end

  | TAst.ClassDefStmt (
        name, body, opt_attr, Some env) ->
     if Env.is_checked env then Env.get_rel_ast env
     else begin
       (* TODO: check duplicate *)
       let name_s = Nodes.string_of_id_string name in
       Printf.printf "class %s - unchecked\n" name_s;
       check_env env;

       (* body *)
       let nbody = analyze_inner body env ctx opt_attr in

       Printf.printf "class %s - complete\n" name_s;
       let node = TAst.ClassDefStmt (
                      name,
                      nbody,
                      opt_attr,
                      Some env
                    ) in

       (* update record *)
       let detail_r = Env.ClsUndef in

       complete_class_env env node
                          name_s detail_r
                          ctx;
       node
     end

  | TAst.ExternClassDefStmt (
        name, extern_cname, opt_attr, Some env) ->
     if Env.is_checked env then Env.get_rel_ast env
     else begin
       (* TODO: check duplicate *)
       let name_s = Nodes.string_of_id_string name in
       Printf.printf "extern class %s - unchecked\n" name_s;
       check_env env;

       (* currently, do not remake a node like other nodes *)
       Printf.printf "extern class %s - complete\n" name_s;

       (* TODO: improve *)
       let is_novalue = match opt_attr with
         | Some tbl ->
            begin
              let v = Hashtbl.find_option tbl "novalue" in
              match v with
                Some vv ->
                begin
                  match vv with
                  | None -> true
                  | _ -> failwith "[ERR] novalue attrbute is not able to have some value"
                end
              | None -> false
            end
         | None -> false
       in

       Printf.printf "is_novalue : %b \n" is_novalue;

       let define_ctor () =
         (* Type of reciever *)
         let ts = Type.UniqueTy env in
         let cr = Env.ClassOp.get_record env in
         let template_args = cr.Env.cls_template_vals in
         let attr = {
           Type_attr.ta_ref_val = Type_attr.Ref;
           Type_attr.ta_mut = Type_attr.Mutable;
         } in
         let ty =
           Type.Generator.generate_type ctx.sc_tsets.ts_type_gen
                                        ts template_args attr
         in

         let ctor_name = "this" in
         (* FIXME: implicit default constructor for primitive *)
         let base_env = Env.MultiSetOp.find_or_add env ctor_name Env.Kind.Function in
         let fenv_r = {
           Env.fn_name = Nodes.Pure ctor_name;
           Env.fn_mangled = None;
           Env.fn_template_vals = [];
           Env.fn_param_types = [];
           Env.fn_return_type = Type.undef_ty;
           Env.fn_detail = Env.FnUndef;
         } in
         let fenv = Env.create_env env (
                                     Env.Function (
                                         Env.empty_lookup_table (),
                                         fenv_r)
                                   ) in
         Env.MultiSetOp.add_normal_instances base_env fenv;
         let node = TAst.GenericFuncDef (None, Some fenv) in
         print_type ty;
         print_type (get_builtin_void_type ctx);
         let detail =
           Env.FnRecordBuiltin (Env.FnDefDefaulted,
                                Env.FnKindConstructor,
                                "default_ctor")
         in
         complete_function_env fenv node "this"
                               []
                               !(ctx.sc_tsets.ts_void_type_holder)
                               detail
                               ctx;

         (* Type of rhs *)
         let ts = Type.UniqueTy env in
         let cr = Env.ClassOp.get_record env in
         let template_args = cr.Env.cls_template_vals in
         let attr = {
           Type_attr.ta_ref_val = Type_attr.Ref;
           Type_attr.ta_mut = Type_attr.Const;
         } in
         let rty =
           Type.Generator.generate_type ctx.sc_tsets.ts_type_gen
                                        ts template_args attr
         in

         (* implicit copy constructor for primitive *)
         let base_env = Env.MultiSetOp.find_or_add env ctor_name Env.Kind.Function in
         let fenv_r = {
           Env.fn_name = Nodes.Pure ctor_name;
           Env.fn_mangled = None;
           Env.fn_template_vals = [];
           Env.fn_param_types = [];
           Env.fn_return_type = Type.undef_ty;
           Env.fn_detail = Env.FnUndef;
         } in
         let fenv = Env.create_env env (
                                     Env.Function (
                                         Env.empty_lookup_table (),
                                         fenv_r)
                                   ) in
         Env.MultiSetOp.add_normal_instances base_env fenv;
         let node = TAst.GenericFuncDef (None, Some fenv) in
         let detail =
           Env.FnRecordBuiltin (Env.FnDefDefaulted,
                                Env.FnKindConstructor,
                                "copy_ctor")
         in
         complete_function_env fenv node "this"
                               [rty]
                               !(ctx.sc_tsets.ts_void_type_holder)
                               detail
                               ctx;

         let op_name = (Nodes.string_of_id_string @@ Nodes.BinaryOp "=") in
         (* implicit copy assignments for primitive *)
         let base_env = Env.MultiSetOp.find_or_add env op_name Env.Kind.Function in
         let fenv_r = {
           Env.fn_name = Nodes.BinaryOp "=";
           Env.fn_mangled = None;
           Env.fn_template_vals = [];
           Env.fn_param_types = [];
           Env.fn_return_type = Type.undef_ty;
           Env.fn_detail = Env.FnUndef;
         } in
         let fenv = Env.create_env env (
                                     Env.Function (
                                         Env.empty_lookup_table (),
                                         fenv_r)
                                   ) in
         Env.MultiSetOp.add_normal_instances base_env fenv;
         let node = TAst.GenericFuncDef (None, Some fenv) in
         let detail =
           Env.FnRecordBuiltin (Env.FnDefDefaulted,
                                Env.FnKindConstructor,
                                "yoyo")
         in
         complete_function_env fenv node op_name
                               [ty; rty]
                               !(ctx.sc_tsets.ts_void_type_holder)
                               detail
                               ctx;

         Printf.printf "======================================================";
       in
       if not is_novalue then
         define_ctor ();

       (* update record *)
       let detail_r = Env.ClsRecordPrimitive {
                          Env.cls_e_name = extern_cname;
                        } in
       let r = Env.ClassOp.get_record env in
       r.Env.cls_detail <- detail_r;

       complete_env env node;
       node
     end

  (* scoped declare *)
  | TAst.VariableDefStmt (v, None) ->
     begin
       let (var_attr, var_name, init_term) =
         match extract_prev_pass_node v with
         | Ast.VarInit vi -> vi
         | _ -> failwith "unexpected node"
       in
       check_id_is_defined_uniquely parent_env var_name;

       let venv = Env.create_env parent_env (
                                   Env.Variable (
                                       {
                                         Env.var_name = var_name;
                                         Env.var_type = Type.undef_ty;
                                         Env.var_detail = Env.VarUndef;
                                       })
                                 )
       in

       let (opt_type, opt_init_value) = init_term in
       let opt_init_value_res =
         opt_init_value
         |> Option.map (fun n -> analyze_expr n parent_env ctx opt_chain_attr)
       in

       (* type check for the variable *)
       let (type_node, value_node, var_ty) = match opt_type with
         (* variable type is specified *)
         | Some var_type_node ->
            begin
              let (expr_ty, type_expr) =
                resolve_type_with_node var_attr var_type_node
                                       parent_env ctx opt_chain_attr
              in
              let var_ty =
                Type.Generator.update_attr_r ctx.sc_tsets.ts_type_gen expr_ty
                                             var_attr
              in
              let res_expr_node = match opt_init_value_res with
                | Some (expr_node, expr_ty) ->
                   begin
                     let (m_level, m_filter) =
                       convert_type var_ty expr_ty parent_env ctx opt_chain_attr
                     in
                     if m_level = FuncMatchLevel.NoMatch then
                       failwith "[ERR] cannot convert type";
                     (* TODO: call filter, call copy/mode ctor *)
                     expr_node
                   end
                | None ->
                   begin
                     (* TODO: implement call defaut constructor *)
                     failwith "not implemented //"
                   end
              in
              (Some type_expr, res_expr_node, var_ty)
            end

         (* var_type is infered from initial_value *)
         | None ->
            begin
              let (expr_node, expr_ty) = match opt_init_value_res with
                | Some v -> v
                | None -> failwith "[ERROR] initial value is required"; (* TODO: call constructor *)
              in
              (* TODO: check void value *)

              let var_ty =
                Type.Generator.update_attr_r ctx.sc_tsets.ts_type_gen expr_ty
                                             var_attr
              in
              let (m_level, m_filter) =
                convert_type var_ty expr_ty parent_env ctx opt_chain_attr
              in
              if m_level = FuncMatchLevel.NoMatch then
                failwith "[ERR] cannot convert type";
              (* TODO: call filter, call copy/mode ctor *)

              (None, expr_node, var_ty)
            end
       in


       (* *)
       Env.add_inner_env parent_env var_name venv;

       let node = TAst.VariableDefStmt (
                      TAst.VarInit (var_attr, var_name, (type_node, Some value_node)),
                      Some venv
                    ) in

       let detail_r = Env.VarRecordNormal () in
       let r = Env.VariableOp.get_record venv in
       r.Env.var_type <- var_ty;
       r.Env.var_detail <- detail_r;

       complete_env venv node;
       node
     end

  | TAst.EmptyStmt -> node

  | _ ->
     begin
       TAst.print node;
       failwith "construct_env: unsupported node or nodes have no valid env"
     end

and analyze_expr ?(making_placeholder=false)
                 node parent_env ctx attr : ('node * type_info_t) =
  match node with
  | Ast.BinaryOpExpr (lhs, op, rhs) ->
     begin
       let args = [lhs; rhs] in
       let eargs = evaluate_invocation_args args parent_env ctx attr in
       let (_, args_types) = List.split eargs in
       List.iter check_is_args_valid args_types;

       List.iter print_type args_types;
       let op_id = Ast.Id (op, ()) in
       let opt_fs_and_args =
         find_suitable_operator ~universal_search:true
                                op_id args_types node parent_env ctx attr in
       match opt_fs_and_args with
       | Some (f_env, conv_filters) ->
          begin
            let n_eargs = map_conversions conv_filters eargs in

            let f_er = Env.FunctionOp.get_record f_env in
            let f_ret_ty = as_ret_ty f_er.Env.fn_return_type ctx in
            assert_valid_type f_ret_ty;

            (* Replace BinOpCall to generic FuncCall *)
            let node = TAst.GenericCall (
                           Nodes.string_of_id_string op,
                           n_eargs,
                           f_ret_ty,
                           Some f_env) in
            (node, f_ret_ty)
          end
       | None ->
          (* TODO: error message *)
          failwith "binary operator is not found"
     end

  | Ast.UnaryOpExpr (op, expr) ->
     begin
       failwith "u op"
     end

  | Ast.CallExpr (reciever, args) ->
     begin
       let (recv_node, recv_type_info) =
         analyze_expr ~making_placeholder:making_placeholder
                      reciever parent_env ctx attr
       in

       let eargs = evaluate_invocation_args args parent_env ctx attr in
       let (_, args_types) = List.split eargs in
       List.iter check_is_args_valid args_types;

       let {
         Type.ti_sort = ty_sort;
         Type.ti_template_args = template_args;
       } = recv_type_info in
       match ty_sort with
       | Type.FunctionSetTy menv ->
          begin
            (* notmal function call*)
            let (f_env, conv_filters) =
              solve_function_overload args_types template_args
                                      menv parent_env ctx attr
            in
            let n_eargs = map_conversions conv_filters eargs in

            let f_er = Env.FunctionOp.get_record f_env in
            let f_ret_ty = as_ret_ty f_er.Env.fn_return_type ctx in
            assert_valid_type f_ret_ty;

            let {
              Env.fn_name = fname;
            } = Env.FunctionOp.get_record f_env in
            let node = TAst.GenericCall (
                           Nodes.string_of_id_string fname,
                           n_eargs,
                           f_ret_ty,
                           Some f_env) in
            (node, f_ret_ty)
          end

       | Type.UniqueTy type_cenv ->
          begin
            (* type_cenv will be Type *)
            Env.print type_cenv;
            let recv_ty =
              resolve_texpr_type { Type_attr.ta_ref_val = Type_attr.Val;
                                   Type_attr.ta_mut = Type_attr.Mutable }
                                 recv_node recv_type_info
                                 parent_env ctx attr
            in
            print_type recv_ty;
            let recv_cenv = Type.as_unique recv_ty in
            Env.print recv_cenv;

            (* call constructor *)
            (* TODO: take into account op call *)
            let ctor_name = Nodes.Pure "this" in
            let res = solve_simple_identifier ~do_rec_search:false
                                              ctor_name recv_cenv ctx attr in
            let (_, ctor_env) = match res with
              | Some v -> v
              | None -> failwith "constructor not found"
            in
            ignore ctor_env;

            let cr = Env.ClassOp.get_record recv_cenv in
            let (f_env, conv_filters) = match cr.Env.cls_detail with
              | Env.ClsRecordPrimitive _ ->
                 (* do NOT insert "this" into arguments when call primitive constructor *)
                 solve_function_overload args_types [] ctor_env parent_env ctx attr
              | _ -> failwith "[ICE]"
            in

            let n_eargs = map_conversions conv_filters eargs in

            let f_er = Env.FunctionOp.get_record f_env in
            let f_ret_ty = as_ret_ty f_er.Env.fn_return_type ctx in
            print_type f_ret_ty;
            assert_valid_type f_ret_ty;

            let {
              Env.fn_name = fname;
            } = Env.FunctionOp.get_record f_env in
            let node = TAst.GenericCall (
                           Nodes.string_of_id_string fname,
                           n_eargs,
                           f_ret_ty,
                           Some f_env) in
            (node, recv_ty)
          end

       | _ -> failwith "not implemented//" (* TODO: call ctor OR operator() *)
     end

  | Ast.StatementTraitsExpr (keyword, block) ->
     begin
       match keyword with
       | "semantics" ->
          begin
            let ty = get_builtin_bool_type ctx in
            let ty =
              Type.Generator.update_attr ctx.sc_tsets.ts_type_gen ty
                                         Type_attr.XRef
                                         Type_attr.Immutable
            in
            assert_valid_type ty;

            let test () =
                (* temporary environment for check whether semantics is valid.
                 * DO NOT append this env to the parent_env.
                 *)
              let temp_env =
                Env.create_env parent_env (Env.Scope (Env.empty_lookup_table ()))
              in
              ignore @@
                analyze ~opt_attr:attr block temp_env ctx;
              true
            in
            let could_compile = try test() with
                                | _ -> false
            in
            let node = TAst.BoolLit (could_compile, ty) in
            (node, ty)
          end
       | _ -> failwith @@ "__statement_traits : not implemented / " ^ keyword
     end

  | (Ast.Id (name, _) as id_node)
  | (Ast.InstantiatedId (name, _, _) as id_node) ->
     begin
       let res =
         solve_identifier ~making_placeholder:making_placeholder
                          id_node parent_env ctx attr
       in
       let (ty, trg_env) = match res with
           Some v -> v
         | None ->
            (* TODO: change to exception *)
            failwith @@ "id not found : " ^ (Nodes.string_of_id_string name)
       in

       (* both of id and instantiated_id will be id node *)
       let node = TAst.Id (name, Some trg_env) in
       (node, ty)
     end

  | Ast.Int32Lit (i, _) ->
     begin
       (* WIP *)
       let ty = get_builtin_int_type ctx in
       let ty =
         Type.Generator.update_attr ctx.sc_tsets.ts_type_gen ty
                                    Type_attr.XRef
                                    Type_attr.Immutable
       in
       assert_valid_type ty;
       let node = TAst.Int32Lit (i, ty) in

       (node, ty)
     end

  | Ast.ArrayLit (elems, _) ->
     begin
       let (n_nodes, n_tys) =
         elems
         |> List.map (fun e -> analyze_expr ~making_placeholder:making_placeholder
                                            e parent_env ctx attr)
         |> List.split
       in
       (* TODO: fix, calc undelying types(and attrs) and convert them *)
       let elem_ty = List.hd n_tys in

       let array_ty = get_builtin_array_type elem_ty (List.length elems) ctx in
       assert_valid_type array_ty;
       let n_array = TAst.ArrayLit (n_nodes, array_ty) in
       (n_array, array_ty)
     end

  | _ ->
     begin
       Ast.print node;
       failwith "analyze_expr: unsupported node"
     end


and analyze_inner node parent_env ctx opt_chain_attr =
  let pre_node = extract_prev_pass_node node in
  analyze ~opt_attr:opt_chain_attr pre_node parent_env ctx

and extract_prev_pass_node node =
  match node with
  | TAst.PrevPassNode n -> n
  | _ -> failwith "[ICE] not prev node"


and prepare_params env func_decl_node params_node ctx attr =
  match extract_prev_pass_node params_node with
  | Ast.ParamsList ps ->
     declare_function_params env func_decl_node ps ctx attr

  | _ -> failwith "check_params / unexpected"


and declare_function_params f_env func_decl_node params ctx attr =
  (*
   * if parameter has name, create variable env
   * DO NOT forget to call Env.add_inner_env
   *)
  let make_parameter_env f_env opt_param_name param_ty ctx =
    let make_env name =
      let detail_r = Env.VarRecordNormal () in
      let venv = Env.create_env f_env (
                                  Env.Variable (
                                      {
                                        Env.var_name = name;
                                        Env.var_type = param_ty;
                                        Env.var_detail = detail_r;
                                      })
                                )
      in
      Env.update_status venv Env.Complete;
      venv
    in
    Option.map make_env opt_param_name
  in

  let analyze_param param =
    let (var_attr, var_name, init_part) = param in
    let (param_ty, default_value) = match init_part with
    (* Ex. :int = 10 *)
    | (Some type_expr, Some defalut_val) ->
       begin
         failwith "declare_function_params : not implemented / default value of param"
       end

    (* Ex. :int *)
    | (Some type_expr, None) ->
       begin
         let ty = resolve_type var_attr type_expr f_env ctx attr in
         (ty, None)
       end

    (* Ex. = 10 *)
    | (None, Some defalut_val) ->
       begin
         (* type is inferenced from defalut_val *)
         failwith "declare_function_params : not implemented / infer type from value"
       end

    | _ ->
       (* TODO: change to exception *)
       failwith "type or default value is required"
    in

    let ninit_part = (None, default_value) in   (* type node is no longer necessary *)
    let nparam : TAst.param_init_t = (var_attr, var_name, ninit_part) in
    (nparam, param_ty)
  in

  let (nparams, (param_types: type_info_t list)) =
    params |> List.map analyze_param |> List.split
  in
  match func_decl_node with
  | TAst.FunctionDefStmt _ ->
     begin
       let make_env param ty =
         let (var_attr, opt_name, _) = param in
         make_parameter_env f_env opt_name ty ctx
       in
       let declare_env param opt_env =
         let declare name =
           let env = Option.get opt_env in
           Env.add_inner_env f_env name env
         in
         let (var_attr, opt_name, _) = param in
         Option.may declare opt_name
       in
       (* first, make environments *)
       let param_envs = List.map2 make_env params param_types in
       (* add var envs to fenv (declare) *)
       List.iter2 declare_env params param_envs;

       (* TODO: support functions that have recievers. ex, member function (this/self) *)
       (nparams, param_types, param_envs)
     end

  | TAst.ExternFunctionDefStmt _ ->
     begin
       (*params*)
       (nparams, param_types, [])
     end

  | _ -> failwith "declare_function_params: not supported"


and check_id_is_defined_uniquely env id =
  let res = Env.find_on_env env id in
  match res with
    Some _ -> failwith "same ids are defined"
  | None -> ()


and solve_identifier ?(do_rec_search=true)
                     ?(making_placeholder=false)
                     id_node env ctx attr
  =
  match id_node with
  | Ast.Id (name, _) ->
     solve_simple_identifier ~do_rec_search:do_rec_search
                             ~making_placeholder:making_placeholder
                             name env ctx attr
  | Ast.InstantiatedId (name, template_args, _) ->
     begin
       Printf.printf "$$$$$ Ast.InstantiatedId\n";
       let (evaled_t_args, _) =
         template_args
         |> List.map (fun e -> eval_expr_as_ctfe e env ctx attr)
         |> List.split
       in
       solve_simple_identifier ~do_rec_search:do_rec_search
                               ~template_args:evaled_t_args
                               ~making_placeholder:making_placeholder
                               name env ctx attr
     end
  | _ -> failwith "unsupported ID type"

and solve_simple_identifier ?(do_rec_search=true)
                            ?(template_args=[])
                            ?(making_placeholder=false)
                            name search_base_env ctx attr
    : (type_info_t * 'env) option =
  (*Env.print env;*)

  (* Class is a value of type, thus returns "type" of type, and corresponding env.
   * Ex, "int" -> { type: type, value: int }
   *)
  let single_type_id_node name cenv attr =
    try_to_complete_env cenv ctx attr;

    (ctx.sc_tsets.ts_type_type, cenv)
  in

  (* TODO: implement merging *)
  let solve (prev_ty, prev_opt_env) env : (type_info_t * 'option) =
    let { Env.er = env_r; _ } = env in
    match env_r with
    | Env.MultiSet (record) ->
       begin
         match record.Env.ms_kind with
         | Env.Kind.Class ->
            begin
              (* classes will not be overloaded. However, template classes have
               * some instances (specialized). Thus, type may be unclear...
               *)
              if List.length record.Env.ms_templates <> 0 then
                match template_args with
                | [] ->
                   let ty =
                     Type.Generator.generate_type ctx.sc_tsets.ts_type_gen
                                                  (Type.ClassSetTy env)
                                                  template_args
                                                  Type_attr.undef
                   in
                   (ty, env)
                | xs ->
                   if making_placeholder then
                     begin
                       (* TODO: fix it *)
                       let uni_id =
                         Unification.generate_uni_id ctx.sc_unification_ctx in
                       Unification.update_type ctx.sc_unification_ctx
                                               uni_id ctx.sc_tsets.ts_type_type;
                       let ty =
                         Type.Generator.generate_type ctx.sc_tsets.ts_type_gen
                                                      (Type.ClassSetTy env)
                                                      template_args
                                                      Type_attr.undef
                       in
                       Unification.update_value ctx.sc_unification_ctx
                                                uni_id (Ctfe_value.Type ty);

                       let ty =
                         Type.Generator.generate_type ctx.sc_tsets.ts_type_gen
                                                      (Type.NotDetermined uni_id)
                                                      template_args
                                                      Type_attr.undef
                       in
                       (ty, env)
                     end
                   else
                     begin
                       let instances =
                         instantiate_class_templates env xs
                                                     search_base_env ctx attr
                       in
                       match instances with
                       | [e] -> (ctx.sc_tsets.ts_type_type, e)
                       | _ -> failwith "[ERR]"
                     end

              else begin
                if (List.length template_args <> 0) then
                  failwith "[ERR] there is no template class";

                match List.length record.Env.ms_normal_instances with
                | 1 ->
                   let single_cenv = List.hd record.Env.ms_normal_instances in
                   single_type_id_node name single_cenv attr
                | _ -> failwith "[ICE] unexpected : class / multi-set"
              end
            end

         | Env.Kind.Function ->
            begin
              (* functions will be overloaded *)
              let ty =
                Type.Generator.generate_type ctx.sc_tsets.ts_type_gen
                                             (Type.FunctionSetTy env)
                                             template_args
                                             Type_attr.undef
              in
              (ty, env)
            end
         | _ -> failwith "unexpected env : multi-set kind"
       end

    (* only builtin classes may be matched *)
    | Env.Class (_) -> single_type_id_node name env attr

    | Env.Variable (vr) ->
       begin
         let {
           Env.var_type = var_ty;
         } = vr in
         (* TODO: check class variable *)

         (var_ty, env)
       end

    (* returns **type** of MetaVariable, NOT value *)
    | Env.MetaVariable (uni_id) ->
       begin
         let (term_uni_id, c) =
           Unification.search_type_until_terminal ctx.sc_unification_ctx uni_id
         in
         match c with
         | (Unification.Val ty) ->
            (ty, env)
         | (Unification.Undef) ->
            let ty =
              Type.Generator.generate_type ctx.sc_tsets.ts_type_gen
                                           (Type.NotDetermined uni_id)
                                           template_args
                                           Type_attr.undef
            in
            (ty, env)
         | _ -> failwith "[ICE] meta ver"
       end

    | _ -> failwith "solve_simple_identifier: unexpected env"
  in

  let name_s = Nodes.string_of_id_string name in
  Printf.printf "-> finding identitifer = %s : rec = %b\n" name_s do_rec_search;
  let oenv = if do_rec_search then
               Env.lookup search_base_env name_s
             else
               Env.find_all_on_env search_base_env name_s
  in
  match oenv with
  | [] -> None
  | envs -> Some (List.fold_left solve (Type.undef_ty, Env.undef ()) envs)


and try_to_complete_env env ctx attr =
  if Env.is_incomplete env then
    match env.Env.rel_node with
    | Some (node) ->
       begin
         let parent_env = Option.get env.Env.parent_env in
         ignore @@ construct_env node parent_env ctx attr;
         if not (Env.is_complete env) then
           failwith "? recursice definition is appeared"; (* TODO: exception *)
         ()
       end
    | None -> failwith "[ICE] try to complete env / "
  else
    ()  (* DO NOTHING *)


and convert_type trg_ty src_ty ext_env ctx attr =
  if Type.is_same trg_ty src_ty then begin
    let open Type_attr in
    match (trg_ty.Type.ti_attr, src_ty.Type.ti_attr) with
    | ({ta_ref_val = Val}, {ta_ref_val = _}) -> (FuncMatchLevel.ExactMatch, None)

    | ({ta_ref_val = Ref; ta_mut = trg_mut},
       {ta_ref_val = _; ta_mut = src_mut}) ->
       begin
         let level = match (trg_mut, src_mut) with
           | (Immutable, Immutable) -> FuncMatchLevel.ExactMatch
           | (Immutable, Const)
           | (Immutable, Mutable) -> FuncMatchLevel.NoMatch

           | (Const, Immutable) -> FuncMatchLevel.QualConv
           | (Const, Const) -> FuncMatchLevel.ExactMatch
           | (Const, Mutable) -> FuncMatchLevel.QualConv

           | (Mutable, Immutable)
           | (Mutable, Const) -> FuncMatchLevel.NoMatch
           | (Mutable, Mutable) -> FuncMatchLevel.ExactMatch

           | _ -> failwith "conv"
         in
         (level, None)
       end

    | _ -> failwith ""
  end else begin
    failwith "convert_type / not implemented"
  end

and is_type_convertible_to src_ty dist_ty =
  if Type.is_same src_ty dist_ty then
    true
  else begin
    failwith "is_type_convertible_to / not implemented"
  end


and resolve_type ?(making_placeholder=false) ty_attr expr env ctx attr =
  let (ctfe_val, _) =
    eval_expr_as_ctfe ~making_placeholder:making_placeholder
                      expr env ctx attr
  in
  extract_ctfe_val_as_type ty_attr ctfe_val ctx

and resolve_texpr_type ?(making_placeholder=false) ty_attr texpr sem_ty env ctx attr =
  let ctfe_val =
    eval_texpr_as_ctfe ~making_placeholder:making_placeholder
                       texpr sem_ty env ctx attr
  in
  extract_ctfe_val_as_type ty_attr ctfe_val ctx

and resolve_type_with_node ?(making_placeholder=false) ty_attr expr env ctx attr =
  let (ctfe_val, nexpr) =
    eval_expr_as_ctfe ~making_placeholder:making_placeholder
                      expr env ctx attr
  in
  let ty = extract_ctfe_val_as_type ty_attr ctfe_val ctx in
  (ty, nexpr)


and extract_ctfe_val_as_type ty_attr ctfe_val ctx =
  match ctfe_val with
  | Ctfe_value.Type ty ->
     Type.Generator.update_attr_r ctx.sc_tsets.ts_type_gen ty ty_attr
  | _ -> failwith "This expression must be type"


and eval_expr_as_ctfe ?(making_placeholder=false) expr env ctx attr =
  Printf.printf "----> eval_expr_as_ctfe : begin ; \n";
  let (nexpr, type_of_expr) =
    analyze_expr ~making_placeholder:making_placeholder
                 expr env ctx attr
  in
  let v = eval_texpr_as_ctfe ~making_placeholder:making_placeholder
                             nexpr type_of_expr
                             env ctx attr
  in
  (v, nexpr)

and eval_texpr_as_ctfe ?(making_placeholder=false) texpr sem_ty env ctx attr =
  let ctfe_val =
    match Type.type_sort sem_ty with
    | Type.UniqueTy _ ->
       Ctfe_engine.execute ctx.sc_ctfe_engine texpr sem_ty ctx.sc_tsets

    | Type.NotDetermined _ ->
       Ctfe_value.Type sem_ty

    | _ -> failwith "[ICE] eval_expr_as_ctfe : couldn't resolve"
  in

  Printf.printf "<---- eval_expr_as_ctfe : end\n";
  ctfe_val


and evaluate_invocation_args args env ctx attr =
  args |> List.map (fun n -> evaluate_invocation_arg n env ctx attr)

and evaluate_invocation_arg expr env ctx attr =
  (* TODO: check CTFE-able node *)
  analyze_expr expr env ctx attr


and find_suitable_operator ?(universal_search=false)
                           op_name_id arg_types expr env ctx attr =
  let opt_callee_function_info =
    select_member_element ~universal_search:universal_search
                          (List.hd arg_types) op_name_id env ctx attr
  in

  let check_type_and_solve_overload (callee_f_ty, callee_f_env) =
    let {
      Type.ti_sort = ty_sort;
      Type.ti_template_args = template_args;
    } = callee_f_ty in
    match ty_sort with
    | Type.FunctionSetTy menv ->
       solve_function_overload arg_types template_args
                               menv env ctx attr
    | _ -> failwith "[ICE]: operator must be defined as function"
  in
  match opt_callee_function_info with
    Some v -> Some (check_type_and_solve_overload v)
  | None -> None


(* returns Env of function *)
and solve_function_overload arg_types tamplate_args mset_env ext_env ctx attr =
  let mset_record = match mset_env.Env.er with
    | Env.MultiSet r -> r
    | _ -> Env.print mset_env;
           failwith "[ICE] solve_function_overload : Only Multiset is accepted"
  in
  if mset_record.Env.ms_kind <> Env.Kind.Function then
    failwith "[ICE] solve_function_overload : sort of menv must be function.";

  let (f_level, fs_and_args) = match tamplate_args with
    (* not template arg *)
    | [] ->
       begin
         let (normal_f_level, normal_fs_and_args) =
           find_suitable_functions mset_record.Env.ms_normal_instances arg_types
                                   ext_env ctx attr
         in
         Printf.printf "!! normal function candidates = %s / %d\n"
                       (FuncMatchLevel.to_string normal_f_level)
                       (List.length normal_fs_and_args);

         match normal_f_level with
         | FuncMatchLevel.ExactMatch ->
            (normal_f_level, normal_fs_and_args)

         (* template functions might have more suitable ones than normal ones *)
         | _ ->
            begin
              let instanced_envs =
                instantiate_function_templates mset_env [] arg_types ext_env ctx attr
              in

              let (instanced_f_level, instanced_fs_and_args) =
                find_suitable_functions instanced_envs arg_types ext_env ctx attr
              in
              Printf.printf "!! instanced function candidates = %s / %d\n"
                            (FuncMatchLevel.to_string instanced_f_level)
                            (List.length instanced_fs_and_args);
              if FuncMatchLevel.is_better instanced_f_level normal_f_level then
                (instanced_f_level, instanced_fs_and_args)
              else
                (normal_f_level, normal_fs_and_args)
            end
     end

  (* has template args *)
  | _ ->
     begin
       let instanced_envs =
         instantiate_function_templates mset_env tamplate_args arg_types
                                        ext_env ctx attr
       in

       find_suitable_functions instanced_envs arg_types ext_env ctx attr
     end
  in

  if f_level = FuncMatchLevel.NoMatch then
    failwith "[ERR] no match";  (* TODO: change to exception *)

  assert (List.length fs_and_args <> 0);
  if (List.length fs_and_args) > 1 then
    failwith "[ERR] anbigous";  (* TODO: change to exception *)

  List.hd fs_and_args


and find_suitable_functions f_candidates arg_types ext_env ctx attr =
  Printf.printf "number of candidates = %d\n" (List.length f_candidates);

  let calc_match_level f_env =
    try_to_complete_env f_env ctx attr;
    let f_record = Env.FunctionOp.get_record f_env in

    (* check number of args *)
    (* TODO: support dynamic variadic args *)
    if (List.length f_record.Env.fn_param_types <> List.length arg_types) then
      (FuncMatchLevel.NoMatch, Env.undef (), [])

    else begin
      let (match_levels, conv_funcs) =
        List.map2 (fun s d -> convert_type d s ext_env ctx attr)
                  arg_types
                  f_record.Env.fn_param_types
        |> List.split
      in

      (* most unmatch level of parameters becomes function match level *)
      let total_f_level =
        List.fold_left FuncMatchLevel.bottom FuncMatchLevel.ExactMatch match_levels in

      (total_f_level, f_env, conv_funcs)
    end
  in

  let collect (cur_order, fs_and_args) candidate =
    let (total_f_level, f_env, conv_funcs) = calc_match_level candidate in
    if FuncMatchLevel.is_better total_f_level cur_order then
      (* if more better function is found, remake candidates and raise level *)
      (total_f_level, [(f_env, conv_funcs)])
    else if FuncMatchLevel.is_same total_f_level cur_order then
      (* if this function has same match level, add to candicates *)
      (cur_order, (f_env, conv_funcs) :: fs_and_args)
    else
      (* ignore(do NOT append) function which has lower match level *)
      (cur_order, fs_and_args)
  in
  let (level, fs_and_args) =
    List.fold_left collect (FuncMatchLevel.NoMatch, []) f_candidates in

  if level = FuncMatchLevel.NoMatch then
    (level, [])
  else
    (level, fs_and_args)


and instantiate_function_templates menv template_args arg_types ext_env ctx attr =
  let instantiate t_env_record =
    let (temp_env, meta_var_names, uni_ids) =
      prepare_instantiate_template t_env_record template_args
                                   ext_env ctx attr
    in

    (* match valuse by arg types *)
    let inner_node = t_env_record.Env.tl_inner_node in
    let inner_node = match inner_node with
      | TAst.PrevPassNode n -> n
      | _ -> failwith ""
    in
    let parameters = match inner_node with
      | Ast.FunctionDefStmt (_, Ast.ParamsList params, _, _, _, _) -> params
      | Ast.ExternFunctionDefStmt (_, Ast.ParamsList params, _, _, _, _) -> params
      | _ -> failwith ""
    in
    let get_param_type (var_attr, _, init) =
      match init with
      | (Some ty_node, _) -> resolve_type ~making_placeholder:true
                                          var_attr ty_node
                                          temp_env ctx attr
      | _ -> failwith "not implemented / param nodes"
    in
    Printf.printf "\n      getting param types =============- \n";
    let param_types = List.map get_param_type parameters in

    List.iter print_type param_types;
    Printf.printf "\n      REACHED / param_types\n";

    let params_type_value = List.map (fun x -> Ctfe_value.Type x) param_types in
    let args_type_value = List.map (fun x -> Ctfe_value.Type x) arg_types in
    Enum.iter2 (unify_arg_value ctx)
               (List.enum params_type_value)
               (List.enum args_type_value);

    Printf.printf "\n      REACHED / unify_arg_type =============- \n";
    List.iter (fun c -> print_meta_var c ctx) uni_ids;

    (**)
    complate_template_instance menv t_env_record
                               meta_var_names uni_ids
                               ctx attr
  in
  let mset_record = Env.MultiSetOp.get_record menv in
  List.map instantiate mset_record.Env.ms_templates


and unify_type ctx lhs rhs =
  let uni_map = ctx.sc_unification_ctx in
  match (lhs, rhs) with
  | ({Type.ti_sort = Type.NotDetermined lhs_uni_t_id;
      Type.ti_template_args = lhs_template_args},
     {Type.ti_sort = Type.NotDetermined rhs_uni_t_id;
      Type.ti_template_args = rhs_template_args}) ->
     begin
       (* TODO: check lhs_template_args and rhs_template_args *)
       Unification.link_type uni_map lhs_uni_t_id rhs_uni_t_id
     end
  | (({Type.ti_sort = (Type.UniqueTy _)} as ty),
     {Type.ti_sort = Type.NotDetermined uni_t_id})
  | ({Type.ti_sort = Type.NotDetermined uni_t_id},
     ({Type.ti_sort = (Type.UniqueTy _)} as ty))
    ->
     begin
       (* TODO: check template args *)
       Unification.update_type uni_map uni_t_id ty
     end
  | _ -> failwith "[ICE] unify_type"


and unify_type_value ctx lhs rhs =
  let uni_map = ctx.sc_unification_ctx in
  match (lhs, rhs) with
  | ({Type.ti_sort = Type.NotDetermined lhs_uni_t_id},
     {Type.ti_sort = Type.NotDetermined rhs_uni_t_id}) ->
     begin
       (* TODO: check template args *)
       Printf.printf "!! unify_type_value(T/T) / %d = %d\n" lhs_uni_t_id rhs_uni_t_id;
       Unification.link_value uni_map lhs_uni_t_id rhs_uni_t_id
     end
  | (({Type.ti_sort = (Type.UniqueTy ty_r); Type.ti_template_args = args} as ty),
     {Type.ti_sort = Type.NotDetermined uni_t_id; Type.ti_template_args = holder_args})
  | ({Type.ti_sort = Type.NotDetermined uni_t_id; Type.ti_template_args = holder_args},
     ({Type.ti_sort = (Type.UniqueTy ty_r); Type.ti_template_args = args} as ty)) ->
     begin
       Printf.printf "!! unify_type_value(T|V) / %d -> value [%d, %d]\n"
                     uni_t_id
                     (List.length args)
                     (List.length holder_args);

       (* TODO: support variadic args *)
       Enum.iter2 (unify_arg_value ctx)
                  (List.enum args)
                  (List.enum holder_args);

       Unification.update_value uni_map uni_t_id (Ctfe_value.Type ty)
     end
  | (({Type.ti_sort = (Type.UniqueTy _)} as lhs_ty),
     ({Type.ti_sort = (Type.UniqueTy _)} as rhs_ty)) ->
     begin
       (* TODO: check template args *)
       if not (is_type_convertible_to rhs_ty lhs_ty) then
         failwith "[ERR] can not convert type"
     end

  | (lhs, rhs) ->
     begin
       Printf.printf "lhs==\n";
       print_type lhs;
       Printf.printf "rhs==\n";
       print_type rhs;
       failwith "[ICE] unify_value_type"
     end


and unify_arg_value ctx lhs rhs =
  match (lhs, rhs) with
  | (Ctfe_value.Type lhs_ty, Ctfe_value.Type rhs_ty) ->
     begin
       unify_type_value ctx lhs_ty rhs_ty
     end
  | (Ctfe_value.Undef uni_id, Ctfe_value.Int32 i32)
  | (Ctfe_value.Int32 i32, Ctfe_value.Undef uni_id) ->
     begin
       Printf.printf "!! unify_meta_value(T|V) / %d -> value\n" uni_id;
       Unification.update_value ctx.sc_unification_ctx uni_id (Ctfe_value.Int32 i32)
     end
  | _ -> failwith "[ICE] not implemented"


and print_type ty =
  match Type.type_sort ty with
  | Type.UniqueTy cenv ->
     begin
       let cls_r = Env.ClassOp.get_record cenv in
       let name = Nodes.string_of_id_string cls_r.Env.cls_name in
       Printf.printf "@==> %s\n" name
     end
  | Type.FunctionSetTy _ -> Printf.printf "function set\n"
  | Type.ClassSetTy _ -> Printf.printf "class set\n"
  | Type.Undef -> Printf.printf "@undef@\n"
  | Type.NotDetermined uni_id ->
     begin
       Printf.printf "@not determined [%d]\n" uni_id
     end


and print_ctfe_value value =
  match value with
  | Ctfe_value.Type ty -> print_type ty
  | Ctfe_value.Int32 n -> Int32.print stdout n
  | Ctfe_value.Undef _ -> Printf.printf "%%ctfe_val(undef)\n"


and print_meta_var uni_id ctx =
  let (_, ty_c) =
    Unification.search_type_until_terminal ctx.sc_unification_ctx uni_id
  in
  let (_, val_c) =
    Unification.search_value_until_terminal ctx.sc_unification_ctx uni_id
  in
  Printf.printf "? type is\n";
  let _ = match ty_c with
    | Unification.Val ty -> print_type ty
    | _ -> Printf.printf "link or undef\n"
  in
  Printf.printf "? value is\n";
  match val_c with
  | Unification.Val value -> print_ctfe_value value
  | _ -> Printf.printf "link or undef\n";


and prepare_template_params params_node ctx =
  match params_node with
  | TAst.PrevPassNode (Ast.TemplateParamsList params) ->
     begin
       let normalize param =
         let (meta_var_name, opt_init) = param in
         match opt_init with
         (* :U *)
         | Some (Some ty, None) -> failwith "not supported"
         (* = V *)
         | Some (None, Some value) -> failwith "not supported"
         (* :U = V *)
         | Some (Some ty, Some value) -> failwith "not supported"
         | Some (None, None) -> failwith "[ICE] unexpected"

         | None -> (meta_var_name, (ctx.sc_tsets.ts_type_type, None))
       in
       List.map normalize params
     end
  | _ -> failwith "[ICE] unexpected template params"


(* this function solves types of the following
* "some_class.some_method"
* When universal_search option is true, a following code will be also solved (for UFCS).
* "some_method"
*)
and select_member_element ?(universal_search=false)
                          recv_ty t_id env ctx attr =
  let recv_cenv = Type.as_unique recv_ty in
  let opt_ty_ctx = solve_identifier ~do_rec_search:false
                                    t_id recv_cenv ctx attr in

  match opt_ty_ctx with
  | Some ty_ctx ->
     begin
       (* member env named id is found in recv_ty_r! *)
       Some ty_ctx
     end

  | None ->
     begin
       (* not found *)
       (* first, find the member function like "opDispatch" in recv_ty_r *)
       (* TODO: implement *)

       (* second, do universal_search *)
       if universal_search then begin
         (* TODO: exclude class envs *)
         solve_identifier t_id env ctx attr

       end else
         None
     end


and prepare_instantiate_template t_env_record template_args ext_env ctx attr =
  Printf.printf "\n-----\n&& start instantiation = %s\n-----\n\n"
                (Nodes.string_of_id_string t_env_record.Env.tl_name);

  let template_params =
    match t_env_record.Env.tl_params with
    | TAst.PrevPassNode (Ast.TemplateParamsList params) -> params
    | _ -> failwith "[ICE] unexpected template params"
  in

  (* In this context, value of MetaVar is treated as TYPE *)

  let (meta_var_names, meta_var_inits) =
    List.split template_params
  in

  (* temporary environment for evaluate meta variables.
   * DO NOT append this env to the parent_env.
   *)
  let temp_env =
    Env.create_env ext_env (Env.Scope (Env.empty_lookup_table ())) in

  (* generate meta variables which have no value and no type *)
  let generate_meta_var name =
    let uni_id =
      Unification.generate_uni_id ctx.sc_unification_ctx in
    let e = Env.create_env temp_env (Env.MetaVariable uni_id) in
    (uni_id, e)
  in
  let (uni_ids, meta_envs) =
    List.map generate_meta_var meta_var_names
    |> List.split
  in
  (* declare *)
  List.iter2 (fun n e -> Env.add_inner_env temp_env n e)
             meta_var_names meta_envs;

  (* let *)
  let get_meta_var_ty_env meta_var_name =
    let s_meta_var_name = Nodes.Pure meta_var_name in
    let opt_meta_var =
      solve_simple_identifier ~do_rec_search:false
                              s_meta_var_name temp_env ctx attr
    in
    let ty_env = match opt_meta_var with
      | Some v -> v
      | None ->
         (*TODO change to exception *)
         failwith "template parameter is not found"
    in
    ty_env
  in

  (* set types of meta var *)
  let set_meta_var_type (var_ty, env) opt_init =
    match opt_init with
    (* :U *)
    | Some (Some ty_expr, None) ->
       let var_attr = {
         Type_attr.ta_ref_val = Type_attr.Ref;
         Type_attr.ta_mut = Type_attr.Immutable;
       } in
       let ty = resolve_type var_attr ty_expr temp_env ctx None in
       unify_type ctx var_ty ty

    (* = V *)
    | Some (None, Some value) -> failwith "not supported"
    (* :U = V *)
    | Some (Some ty, Some value) -> failwith "not supported"
    | Some (None, None) -> failwith "[ICE] unexpected"

    | None ->
       begin
         match Type.type_sort var_ty with
         | Type.NotDetermined uni_t_id ->
            unify_type ctx var_ty ctx.sc_tsets.ts_type_type;

         | _ -> failwith "not implemented 01"
       end
  in
  let meta_vars_ty_env = List.map get_meta_var_ty_env meta_var_names in
  List.iter2 set_meta_var_type meta_vars_ty_env meta_var_inits;

  Printf.printf "== PRINT META VARIABLES (after type set)\n";
  List.iter (fun c -> print_meta_var c ctx) uni_ids;

  let set_default_value meta_var =
    let (ty, uni_id) = match meta_var with
      | (ty, {Env.er = Env.MetaVariable (uni_id)}) -> (ty, uni_id)
      | _ -> failwith ""
    in
    if Type.has_same_class ty ctx.sc_tsets.ts_type_type then
      begin
        let ud_ty =
          Type.Generator.generate_type ctx.sc_tsets.ts_type_gen
                                       (Type.NotDetermined uni_id)
                                       []
                                       Type_attr.undef
        in
        let type_val = Ctfe_value.Type ud_ty in
        Unification.update_value ctx.sc_unification_ctx uni_id type_val;
        type_val
      end
    else
      let undef_val = Ctfe_value.Undef uni_id in
      Unification.update_value ctx.sc_unification_ctx uni_id undef_val;
      undef_val
  in
  let template_params_default_values =
    meta_var_names
    |> List.map get_meta_var_ty_env
    |> List.map set_default_value
  in

  Printf.printf "== PRINT META VARIABLES (after default value set)\n";
  List.iter (fun c -> print_meta_var c ctx) uni_ids;

  Printf.printf "\nREACHED / set_default_value\n";

  Printf.printf "len(template_params_default_values) = %d\n"
                (List.length template_params_default_values);
  Printf.printf "len(template_args) = %d\n"
                (List.length template_args);

  (* match values by template args *)
  Enum.iter2 (unify_arg_value ctx)
             (List.enum template_params_default_values)
             (List.enum template_args);

  Printf.printf "\nREACHED / unify_arg_value\n";

  (* TODO: assign default template parameter values *)
  (temp_env, meta_var_names, uni_ids)

and complate_template_instance ?(making_placeholder=false)
                               menv t_env_record meta_var_names uni_ids ctx attr =
  let normalize_meta_var uni_id =
    let normalize_uni_value uni_id =
      let (last_uni_id, c) =
        Unification.search_value_until_terminal ctx.sc_unification_ctx uni_id
      in
      match c with
      | Unification.Val v ->
         begin
           match v with
           | Ctfe_value.Undef _ -> failwith "[ERR] not resolved"
           | _ -> Unification.update_value ctx.sc_unification_ctx uni_id v
         end
      | _ -> failwith "[ERR] not resolved"
    in
    let normalize_uni_type uni_id =
      let (last_uni_id, c) =
        Unification.search_type_until_terminal ctx.sc_unification_ctx uni_id
      in
      match c with
      | Unification.Val v ->
         Unification.update_type ctx.sc_unification_ctx uni_id v
      | _ -> failwith "[ERR] not resolved"
    in

    normalize_uni_type uni_id;
    normalize_uni_value uni_id
  in
  List.iter normalize_meta_var uni_ids;

  let mangled_sym =
    uni_ids
    |> List.map (Unification.get_as_value ctx.sc_unification_ctx)
    |> (fun x -> Mangle.s_of_template_args x ctx.sc_tsets)
  in
  String.print stdout mangled_sym;

  let mset_record = Env.MultiSetOp.get_record menv in
  let inner_node = match t_env_record.Env.tl_inner_node with
    | TAst.PrevPassNode n -> n
    | _ -> failwith ""
  in

  let cache = Hashtbl.find_option mset_record.Env.ms_instanced_args_memo mangled_sym in
  match cache with
  | Some env -> env (* DO NOTHING, because this template is already generated *)
  | None ->
     begin
       let mvs = List.combine meta_var_names uni_ids in

       (**)
       let env_parent = Option.get menv.Env.parent_env in
       let n_ast = analyze ~meta_variables:mvs inner_node env_parent ctx in

       let i_env = match n_ast with
         | TAst.FunctionDefStmt (_, _, _, _, _, Some e)
         | TAst.ExternFunctionDefStmt (_, _, _, _, _, Some e) -> e
         | TAst.ExternClassDefStmt (_, _, _, Some e) -> e
         | _ -> failwith "[ICE] complete template / cache"
       in

       Hashtbl.add mset_record.Env.ms_instanced_args_memo mangled_sym i_env;
       i_env
     end


(* XXX: should ext_env be parent env of menv...? *)
and instantiate_class_templates menv template_args ext_env ctx attr =
  let instantiate t_env_record =
    let (temp_env, meta_var_names, uni_ids) =
      prepare_instantiate_template t_env_record template_args
                                   ext_env ctx attr
    in
    complate_template_instance menv t_env_record
                               meta_var_names uni_ids
                               ctx attr
  in
  let mset_record = Env.MultiSetOp.get_record menv in
  List.map instantiate mset_record.Env.ms_templates


and map_conversions filters eargs =
  let (exprs, types) = eargs |> List.split in
  exprs


and get_builtin_int_type ?(bits=32) ?(signed=true)
                         ctx : 'env type_info =
  let ty = match bits with
    | 32 -> if signed then
              !(ctx.sc_tsets.ts_int32_type_holder)
            else
              failwith "[ICE] get builtin int type"
    | _ -> failwith "[ICE] unsupported bits size"
  in
  assert (not @@ Type.is_undef ty);
  ty

and get_builtin_void_type ctx : 'env type_info =
  let ty = !(ctx.sc_tsets.ts_void_type_holder) in
  assert (not @@ Type.is_undef ty);
  ty

and get_builtin_bool_type ctx : 'env type_info =
  let ty = !(ctx.sc_tsets.ts_bool_type_holder) in
  assert (not @@ Type.is_undef ty);
  ty

and get_builtin_array_type elem_ty len ctx : 'env type_info =
  let arr_ty = !(ctx.sc_tsets.ts_array_type_holder) in
  assert (not @@ Type.is_undef arr_ty);

  Printf.printf "========= Array Element\n";
  print_type elem_ty;

  let ty = match Type.type_sort arr_ty with
    | Type.ClassSetTy menv ->
       begin
         let template_args = [Ctfe_value.Type elem_ty;
                              Ctfe_value.Int32 (Int32.of_int len)
                             ] in
         let ext_env = Option.get menv.Env.parent_env in
         let instances =
           instantiate_class_templates menv template_args
                                       ext_env ctx None
         in
         match instances with
         | [e] ->
            Type.Generator.generate_type ctx.sc_tsets.ts_type_gen
                                         (Type.UniqueTy e)
                                         template_args
                                         Type_attr.undef
         | _ -> failwith "[ICE] unexpected array instances"
       end
    | _ -> failwith "[ICE] unexpected"
  in
  print_type ty;
  ty

(* *)
and cache_builtin_type_info preset_ty name ctx =
  Printf.printf "get_builtin_type_info = %s\n" name;
  match Type.type_sort !preset_ty with
  (* not defined yet *)
  | Type.Undef ->
     begin
       let res =
         solve_simple_identifier ~do_rec_search:false
                                 (Nodes.Pure name)
                                 (Option.get ctx.sc_builtin_m_env) ctx None
       in
       match res with
       (* pure type *)
       | Some (ty, c_env) when ty == ctx.sc_tsets.ts_type_type ->
          begin
            let default_ty_attr = {
              Type_attr.ta_ref_val = Type_attr.Val;
              Type_attr.ta_mut = Type_attr.Const;
            } in
            let prim_ty =
              Type.Generator.generate_type ctx.sc_tsets.ts_type_gen
                                           (Type.UniqueTy c_env)
                                           []
                                           default_ty_attr
            in
            preset_ty := prim_ty;
          end

       (* template class *)
       | Some (ty, menv) when Type.is_class_set ty ->
          begin
            preset_ty := ty;
          end

       (**)
       | _ -> failwith "[ICE] cache_builtin_type_info: no definition"
     end

  (* already defined *)
  | _ -> ()


and analyze ?(meta_variables=[]) ?(opt_attr=None) node env ctx =
  let snode = solve_forward_refs ~meta_variables:meta_variables node env ctx in
  construct_env snode env ctx opt_attr
