//
// Copyright yutopp 2013 - .
//
// Distributed under the Boost Software License, Version 1.0.
// (See accompanying file LICENSE_1_0.txt or copy at
// http://www.boost.org/LICENSE_1_0.txt)
//

#pragma once

#include <iostream>
#include <cstddef>

#include "config/macros.hpp"

#include "environment_fwd.hpp"

#include "value_fwd.hpp"
#include "expression_fwd.hpp"
#include "statement_fwd.hpp"

struct value_env_pair_t
{
    value_ptr value;
    const_environment_ptr env;
};
value_env_pair_t const nullexpr;



std::ostream& operator<<( std::ostream& os, value_env_pair_t const& v );

inline auto make_value_env_pair( value_ptr const& v, const_environment_ptr const& e )
    -> value_env_pair_t
{
    value_env_pair_t r = { v, e };
    return r;
}

inline auto make_value_env_pair( const_environment_ptr const& e )
    -> value_env_pair_t
{
    value_env_pair_t r = { nullptr, e };
    return r;
}

struct tree_visitor_base
{
public:
    virtual ~tree_visitor_base() {}

public:
    // statement_list
    virtual void operator()( statement_list const& ss, environment_ptr const& env ) const =0;

    // statement
    // virtual void operator()( template_statement const& s, environment_ptr const& env ) const =0;

    virtual void operator()( expression_statement const& s, environment_ptr const& env ) const =0;
    virtual void operator()( return_statement const& s, environment_ptr const& env ) const =0;
    virtual void operator()( function_definition_statement const& s, environment_ptr const& env ) const =0;
    // virtual void operator()( native_function_definition_statement const& s, environment_ptr const& env ) const =0;

    virtual void operator()( class_definition_statement const& s, environment_ptr const& env ) const =0;


    // expression
    virtual value_env_pair_t operator()( binary_operator_expression const& s, environment_ptr const& env ) const =0;
    virtual value_env_pair_t operator()( call_expression const& s, environment_ptr const& env ) const =0;
    virtual value_env_pair_t operator()( embedded_function_call_expression const& s, environment_ptr const& env ) const =0;
    virtual value_env_pair_t operator()( term_expression const& s, environment_ptr const& env ) const =0;

    // value
    virtual const_environment_ptr operator()( literal_value const& s, environment_ptr const& env ) const =0;
    virtual auto operator()( variable_value const& s, environment_ptr const& env ) const -> const_environment_ptr =0;

public:
    // filter outdated object
    template<typename T>
    std::nullptr_t operator()( T const&, environment_ptr const& ) const
    {
        std::cerr
            << "DEBUG: message. please implement it!" << std::endl
            << "-> " << typeid(T).name() << std::endl;

        return nullptr;
    }
};