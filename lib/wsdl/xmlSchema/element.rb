# WSDL4R - XMLSchema element definition for WSDL.
# Copyright (C) 2002, 2003, 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'


module WSDL
module XMLSchema


class Element < Info
  class << self
    def attr_reader_ref(symbol)
      name = symbol.to_s
      self.__send__(:define_method, name, proc {
        instance_variable_get("@#{name}") ||
          (refelement ? refelement.__send__(name) : nil)
      })
    end
  end

  attr_writer :name	# required
  attr_writer :type
  attr_writer :local_simpletype
  attr_writer :local_complextype
  attr_writer :constraint
  attr_writer :maxoccurs
  attr_writer :minoccurs
  attr_writer :nillable

  attr_reader_ref :name
  attr_reader_ref :type
  attr_reader_ref :local_simpletype
  attr_reader_ref :local_complextype
  attr_reader_ref :constraint
  attr_reader_ref :maxoccurs
  attr_reader_ref :minoccurs
  attr_reader_ref :nillable

  attr_accessor :ref

  def initialize(name = nil, type = nil)
    super()
    @name = name
    @type = type
    @local_simpletype = @local_complextype = nil
    @constraint = nil
    @maxoccurs = '1'
    @minoccurs = '1'
    @nillable = nil
    @ref = nil
    @refelement = nil
  end

  def refelement
    @refelement ||= root.collect_elements[@ref]
  end

  def targetnamespace
    parent.targetnamespace
  end

  def elementform
    # ToDo: must be overwritten.
    parent.elementformdefault
  end

  def parse_element(element)
    case element
    when SimpleTypeName
      @local_simpletype = SimpleType.new
      @local_simpletype
    when ComplexTypeName
      @type = nil
      @local_complextype = ComplexType.new
      @local_complextype
    when UniqueName
      @constraint = Unique.new
      @constraint
    else
      nil
    end
  end

  def parse_attr(attr, value)
    case attr
    when NameAttrName
      @name = XSD::QName.new(targetnamespace, value.source)
    when TypeAttrName
      @type = value
    when RefAttrName
      @ref = value
    when MaxOccursAttrName
      if parent.is_a?(All)
	if value.source != '1'
	  raise Parser::AttrConstraintError.new("cannot parse #{value} for #{attr}")
	end
      end
      @maxoccurs = value.source
    when MinOccursAttrName
      if parent.is_a?(All)
	unless ['0', '1'].include?(value.source)
	  raise Parser::AttrConstraintError.new("cannot parse #{value} for #{attr}")
	end
      end
      @minoccurs = value.source
    when NillableAttrName
      @nillable = (value.source == 'true')
    else
      nil
    end
  end
end


end
end
