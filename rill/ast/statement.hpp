//
// Copyright yutopp 2013 - .
//
// Distributed under the Boost Software License, Version 1.0.
// (See accompanying file LICENSE_1_0.txt or copy at
// http://www.boost.org/LICENSE_1_0.txt)
//

#pragma once

#include <vector>
#include <string>

#include <boost/optional.hpp>

#include "../environment_fwd.hpp"

#include "detail/tree_visitor_base.hpp"
#include "detail/dispatch_assets.hpp"

#include "statement_fwd.hpp"

#include "value.hpp"
#include "expression.hpp"


namespace rill
{
    namespace ast
    {
        // ----------------------------------------------------------------------
        // ----------------------------------------------------------------------
        //
        // statements
        //
        // ----------------------------------------------------------------------
        // ----------------------------------------------------------------------

        // 
        struct statement
        {
        public:
            RILL_AST_ADAPT_VISITOR( statement )

        public:
            virtual ~statement()
            {};
        };


        enum class variable_kind
        {
            k_val = 10,
            k_ref = 20
        };

        enum class modifiability_attribute_kind
        {
            k_mutable,
            k_const,
            k_immutable,
        };


        struct type_attributes
        {
            boost::optional<modifiability_attribute_kind> modifiability;
        };


        //
        struct value_initializer_unit
        {
            expression_ptr initializer;
            type_expression_ptr type;
            
        };


        struct variable_declaration_unit
        {
            intrinsic::single_identifier_value_base_ptr name;
            value_initializer_unit init_unit;
        };


        typedef std::vector<variable_declaration_unit> variable_declaration_unit_list;


        struct variable_declaration
        {
            // TODO: add declaration type information(Ex. val OR ref... and so on
            variable_kind kind;
            variable_declaration_unit decl_unit;
        };


        // TODO: change to declaration statement
        typedef std::vector<variable_declaration> parameter_list;

        /*
        // TODO: change to declaration statement
        inline auto make_variable_declaration(
            intrinsic::identifier_value_ptr const& name = nullptr,
            expression_ptr const& initializer = nullptr,
            type_expression_ptr const& type = nullptr
            )
            -> variable_declaration_unit
        {
            value_initializer_unit vi = { initializer, type };
            variable_declaration_unit du = { name, vi };

            return du;
        }


        // TODO: change to declaration statement
        inline auto make_variable_declaration(
            intrinsic::identifier_value_ptr const& name = nullptr,
            expression_ptr const& initializer = nullptr,
            type_expression_ptr const& type = nullptr
            )
            -> variable_declaration_unit
        {
            value_initializer_unit vi = { initializer, type };
            variable_declaration_unit du = { name, vi };

            return du;
        }
        */
/*
        // test imprementation
        inline auto make_parameter_list(
            parameter_pair const& pp
            )
            -> parameter_list
        {
            parameter_list pl;
            pl.push_back( pp ); // test code

            return pl;
        }
        */


        //
        template<typename Target>
        struct template_statement
            : statement
        {
        public:
//            RILL_AST_ADAPT_VISITOR( template_statement )
        };




        struct expression_statement
            : public statement
        {
        public:
            RILL_AST_ADAPT_VISITOR( expression_statement )

        public:
            expression_statement( expression_ptr const& expr )
                : expression_( expr )
            {}

        public:
            expression_ptr const expression_;
        };


        struct empty_statement
            : public statement
        {
        public:
            RILL_AST_ADAPT_VISITOR( empty_statement )

        public:
            empty_statement()
            {}
        };



        struct extern_statement_base
            : public statement
        {
        public:
            virtual ~extern_statement_base()
            {}
        };


        struct extern_function_declaration_statement
            : public extern_statement_base
        {
        public:
            RILL_AST_ADAPT_VISITOR( extern_function_declaration_statement )

        public:
            extern_function_declaration_statement(
                intrinsic::identifier_value_ptr const& symbol_name,
                parameter_list const& parameter_list,
                boost::optional<intrinsic::identifier_value_ptr> const& return_type,
                native_string_t const& extern_symbol_name
                )
                : identifier_( symbol_name )
                , parameter_list_( parameter_list )
                , return_type_( return_type )
                , extern_symbol_name_( extern_symbol_name )
            {}

        public:
            auto get_identifier() const
                -> intrinsic::identifier_value_ptr
            {
                return identifier_;
            }

            auto get_parameter_list() const
                -> parameter_list
            {
                return parameter_list_;
            }

            auto get_extern_symbol_name() const
                -> native_string_t
            {
                return extern_symbol_name_;
            }

        public:
            intrinsic::identifier_value_ptr identifier_;
            parameter_list parameter_list_;
            boost::optional<intrinsic::identifier_value_ptr> return_type_;

            native_string_t extern_symbol_name_;
        };






        struct function_definition_statement_base
            : public statement
        {
//            ADAPT_STATEMENT_VISITOR( function_definition_statement_base )

        public:
            function_definition_statement_base( statement_list const& statements )
                : statements_( statements )
            {}

            virtual ~function_definition_statement_base()
            {}

        public:


        public:
            statement_list const statements_;
        };



        struct function_definition_statement
            : public function_definition_statement_base
        {
        public:
            RILL_AST_ADAPT_VISITOR( function_definition_statement )

        public:
            function_definition_statement(
                intrinsic::identifier_value_ptr const& symbol_name,
                parameter_list const& parameter_list,
                boost::optional<intrinsic::identifier_value_ptr> const& return_type,
                statement_list const& statements
                )
                : function_definition_statement_base( statements )
                , identifier_( symbol_name )
                , parameter_list_( parameter_list )
                , return_type_( return_type )
            {}

        public:
            auto get_identifier() const
                -> intrinsic::identifier_value_ptr
            {
                return identifier_;
            }

            auto get_parameter_list() const
                -> parameter_list
            {
                return parameter_list_;
            }

        public:
            intrinsic::identifier_value_ptr identifier_;
            parameter_list parameter_list_;
            boost::optional<intrinsic::identifier_value_ptr> return_type_;
        };


        struct embedded_function_definition_statement
            : public function_definition_statement_base
        {
        public:
            RILL_AST_ADAPT_VISITOR( embedded_function_definition_statement )

        public:
            embedded_function_definition_statement( statement_list const& statements )
                : function_definition_statement_base( statements )
            {}
        };



        struct variable_declaration_statement
            : public statement
        {
        public:
            RILL_AST_ADAPT_VISITOR( variable_declaration_statement )

        public:
            variable_declaration_statement( variable_declaration const& decl )
                : declaration_( decl )
            {}

        public:
            variable_declaration const declaration_;
        };


        struct return_statement
            : public statement
        {
        public:
            RILL_AST_ADAPT_VISITOR( return_statement )

        public:
            return_statement( expression_ptr const& expr )
                : expression_( expr )
            {}

        public:
            expression_ptr const expression_;
        };






        struct class_definition_statement
            : public statement
        {
        public:
            RILL_AST_ADAPT_VISITOR( class_definition_statement )

        public:
            class_definition_statement( intrinsic::identifier_value_ptr const& identifier )
                : identifier_( identifier )
            {}

            //virtual ~class_definition_statement {}

        public:
            //void setup_environment( environment_ptr const& ) const {}

            auto get_identifier() const
                -> intrinsic::identifier_value_ptr
            {
                return identifier_;
            }

        private:
            intrinsic::identifier_value_ptr identifier_;
        };



        // make native
        inline auto make_native_class( intrinsic::identifier_value_ptr const& class_name )
            -> class_definition_statement_ptr
        {
            // TODO: insert assert that checks class_name depth.

            return std::make_shared<class_definition_statement>( class_name );
        }






        struct block_statement
            : public statement
        {
//            ADAPT_STATEMENT_VISITOR( block_statement )

        public:
            block_statement( statement_list const& statements )
                : statements_( statements )
            {}

        public:
            statement_list statements_;
        };

    } // namespace ast
} // namespace rill


BOOST_FUSION_ADAPT_STRUCT(
    rill::ast::type_attributes,
    (boost::optional<rill::ast::modifiability_attribute_kind>,  modifiability)
    )


BOOST_FUSION_ADAPT_STRUCT(
    rill::ast::value_initializer_unit,
    (rill::ast::expression_ptr,      initializer)
    (rill::ast::type_expression_ptr, type)
    )

BOOST_FUSION_ADAPT_STRUCT(
    rill::ast::variable_declaration_unit,
    (rill::ast::intrinsic::single_identifier_value_base_ptr,    name)
    (rill::ast::value_initializer_unit,                         init_unit)
    )

BOOST_FUSION_ADAPT_STRUCT(
    rill::ast::variable_declaration,
    (rill::ast::variable_kind,              kind)
    (rill::ast::variable_declaration_unit,  decl_unit)
    )

