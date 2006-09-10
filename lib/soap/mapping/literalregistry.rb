# SOAP4R - literal mapping registry.
# Copyright (C) 2004-2006  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'soap/baseData'
require 'soap/mapping/mapping'
require 'soap/mapping/typeMap'
require 'xsd/codegen/gensupport'
require 'xsd/namedelements'


module SOAP
module Mapping


class LiteralRegistry
  include RegistrySupport

  attr_accessor :excn_handler_obj2soap
  attr_accessor :excn_handler_soap2obj

  def initialize
    super()
    @excn_handler_obj2soap = nil
    @excn_handler_soap2obj = nil
    @class_schema_definition = {}
    @qname_schema_definition = {}
  end

  def add(obj_class, definition)
    definition = Mapping.create_schema_definition(obj_class, definition)
    @class_schema_definition[obj_class] = definition
    if definition.name
      qname = XSD::QName.new(definition.ns, definition.name)
      @qname_schema_definition[qname] = [obj_class, definition]
    end
    if definition.type
      qname = XSD::QName.new(definition.ns, definition.type)
      @qname_schema_definition[qname] = [obj_class, definition]
    end
  end

  def obj2soap(obj, qname)
    soap_obj = nil
    if obj.is_a?(SOAPElement)
      soap_obj = obj
    else
      soap_obj = any2soap(obj, qname)
    end
    return soap_obj if soap_obj
    if @excn_handler_obj2soap
      soap_obj = @excn_handler_obj2soap.call(obj) { |yield_obj|
        Mapping.obj2soap(yield_obj, nil, nil, MAPPING_OPT)
      }
      return soap_obj if soap_obj
    end
    raise MappingError.new("cannot map #{obj.class.name} as #{qname}")
  end

  # node should be a SOAPElement
  def soap2obj(node, obj_class = nil)
    # obj_class is given when rpc/literal service.  but ignored for now.
    begin
      return any2obj(node)
    rescue MappingError
    end
    if @excn_handler_soap2obj
      begin
        return @excn_handler_soap2obj.call(node) { |yield_node|
	    Mapping.soap2obj(yield_node, nil, nil, MAPPING_OPT)
	  }
      rescue Exception
      end
    end
    if node.respond_to?(:type)
      raise MappingError.new("cannot map #{node.type.name} to Ruby object")
    else
      raise MappingError.new("cannot map #{node.elename.name} to Ruby object")
    end
  end

private

  MAPPING_OPT = { :no_reference => true }

  def any2soap(obj, qname)
    ele = nil
    if definition = schema_definition_from_class(obj.class)
      ele = stubobj2soap(obj, qname, definition)
    elsif obj.is_a?(SOAP::Mapping::Object)
      ele = mappingobj2soap(obj, qname)
    elsif obj.is_a?(Hash)
      ele = SOAPElement.from_obj(obj)
      ele.elename = qname
    elsif obj.is_a?(Array)
      # treat as a list of simpletype
      ele = SOAPElement.new(qname, obj.join(" "))
    elsif obj.is_a?(XSD::QName)
      ele = SOAPElement.new(qname)
      ele.text = obj
    else
      # expected to be a basetype or an anyType.
      # SOAPStruct, etc. is used instead of SOAPElement.
      begin
        ele = Mapping.obj2soap(obj, nil, nil, MAPPING_OPT)
        ele.elename = qname
      rescue MappingError
        ele = SOAPElement.new(qname, obj.to_s)
      end
    end
    add_attributes2soap(obj, ele)
    ele
  end

  def stubobj2soap(obj, qname, definition)
    if obj.is_a?(::String)
      ele = SOAPElement.new(qname, obj)
    else
      ele = SOAPElement.new(qname)
    end
    ele.qualified = definition.qualified
    ele.extraattr[XSD::AttrTypeName] =
      XSD::QName.new(definition.ns, definition.type)
    any = nil
    if definition.have_any?
      any = Mapping.get_attributes_for_any(obj, definition.elements)
    end
    definition.elements.each do |eledef|
      if eledef.elename == XSD::AnyTypeName
        if any
          SOAPElement.from_objs(any).each do |child|
            ele.add(child)
          end
        end
      elsif child = Mapping.get_attribute(obj, eledef.varname)
        if eledef.as_array?
          child.each do |item|
            ele.add(obj2soap(item, eledef.elename))
          end
        else
          ele.add(obj2soap(child, eledef.elename))
        end
      elsif obj.respond_to?(:each) and eledef.as_array?
        obj.each do |item|
          ele.add(obj2soap(item, eledef.elename))
        end
      end
    end
    ele
  end

  def mappingobj2soap(obj, qname)
    ele = SOAPElement.new(qname)
    obj.__xmlele.each do |key, value|
      if value.is_a?(::Array)
        value.each do |item|
          ele.add(obj2soap(item, key))
        end
      else
        ele.add(obj2soap(value, key))
      end
    end
    ele
  end

  def any2obj(node, obj_class = nil)
    if obj_class
      definition = schema_definition_from_class(obj_class)
    else
      obj_class, definition = schema_definition_from_qname(node.elename)
      unless obj_class
        typestr = XSD::CodeGen::GenSupport.safeconstname(node.elename.name)
        obj_class = Mapping.class_from_name(typestr)
        definition = schema_definition_from_class(obj_class) if obj_class
      end
    end
    if node.is_a?(SOAPElement) or node.is_a?(SOAPStruct)
      if definition
        return elesoap2stubobj(node, obj_class, definition)
      else
        # SOAPArray for literal?
        return elesoap2plainobj(node)
      end
    end
    obj = Mapping.soap2obj(node, nil, obj_class, MAPPING_OPT)
    add_attributes2obj(node, obj)
    obj
  end

  def elesoap2stubobj(node, obj_class, definition)
    obj = Mapping.create_empty_object(obj_class)
    add_elesoap2stubobj(node, obj, definition)
    add_attributes2stubobj(node, obj, definition)
    obj
  end

  def elesoap2plainobj(node)
    obj = anytype2obj(node)
    add_elesoap2plainobj(node, obj)
    add_attributes2obj(node, obj)
    obj
  end

  def anytype2obj(node)
    if node.is_a?(::SOAP::SOAPBasetype)
      return node.data
    end
    klass = ::SOAP::Mapping::Object
    obj = klass.new
    obj
  end

  def add_elesoap2stubobj(node, obj, definition)
    vars = {}
    node.each do |name, value|
      item = definition.elements.find { |k, v| k.elename.name == name }
      if item
        child = elesoapchild2obj(value, definition.ns, item)
      else
        # unknown element is treated as anyType.
        child = any2obj(value)
      end
      if item and item.as_array?
        (vars[name] ||= []) << child
      else
        vars[name] = child
      end
    end
    if obj.is_a?(::Array)
      obj.replace(vars.values.flatten)
    else
      Mapping.set_attributes(obj, vars)
    end
  end

  def elesoapchild2obj(value, ns, eledef)
    obj_class, child_definition = schema_definition_from_qname(eledef.elename)
    if child_definition
      any2obj(value, obj_class)
    elsif eledef.type
      obj_class, child_definition =
        schema_definition_from_qname(XSD::QName.new(ns, eledef.type))
      if child_definition
        any2obj(value, obj_class)
      elsif klass = Mapping.class_from_name(eledef.type)
        # klass must be a SOAPBasetype or a class
        if klass.ancestors.include?(::SOAP::SOAPBasetype)
          if value.respond_to?(:data)
            klass.new(value.data).data
          else
            klass.new(nil).data
          end
        else
          any2obj(value, klass)
        end
      elsif klass = Mapping.module_from_name(eledef.type)
        # simpletype
        if value.respond_to?(:data)
          value.data
        else
          raise MappingError.new("cannot map to a module value: #{eledef.type}")
        end
      else
        raise MappingError.new("unknown class/module: #{eledef.type}")
      end
    else
      # untyped element is treated as anyType.
      any2obj(value)
    end
  end

  def add_attributes2stubobj(node, obj, definition)
    if attributes = definition.attributes
      define_xmlattr(obj)
      attributes.each do |qname, class_name|
        attr = node.extraattr[qname]
        next if attr.nil? or attr.empty?
        klass = Mapping.class_from_name(class_name)
        if klass.ancestors.include?(::SOAP::SOAPBasetype)
          child = klass.new(attr).data
        else
          child = attr
        end
        obj.__xmlattr[qname] = child
        define_xmlattr_accessor(obj, qname)
      end
    end
  end

  def add_elesoap2plainobj(node, obj)
    node.each do |name, value|
      obj.__add_xmlele_value(value.elename, any2obj(value))
    end
  end

  def add_attributes2obj(node, obj)
    return if node.extraattr.empty?
    define_xmlattr(obj)
    node.extraattr.each do |qname, value|
      obj.__xmlattr[qname] = value
      define_xmlattr_accessor(obj, qname)
    end
  end

  # Mapping.define_attr_accessor calls define_method with proc and it exhausts
  # much memory for each singleton Object.  just instance_eval instead of it.
  def define_xmlattr_accessor(obj, qname)
    # untaint depends GenSupport.safemethodname
    name = XSD::CodeGen::GenSupport.safemethodname('xmlattr_' + qname.name).untaint
    # untaint depends QName#dump
    qnamedump = qname.dump.untaint
    obj.instance_eval <<-EOS
      def #{name}
        @__xmlattr[#{qnamedump}]
      end

      def #{name}=(value)
        @__xmlattr[#{qnamedump}] = value
      end
    EOS
  end

  # Mapping.define_attr_accessor calls define_method with proc and it exhausts
  # much memory for each singleton Object.  just instance_eval instead of it.
  def define_xmlattr(obj)
    obj.instance_variable_set('@__xmlattr', {})
    unless obj.respond_to?(:__xmlattr)
      obj.instance_eval <<-EOS
        def __xmlattr
          @__xmlattr
        end
      EOS
    end
  end

  def schema_definition_from_class(klass)
    @class_schema_definition[klass] || Mapping.schema_definition_classdef(klass)
  end

  def class_from_schema_definition(definition)
    @class_schema_definition.key(definition)
  end

  def schema_definition_from_qname(qname)
    @qname_schema_definition[qname]
  end
end


end
end
