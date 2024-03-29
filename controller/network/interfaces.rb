require 'pp'
require 'sinatra/base'

require 'wiedii/network/interface'

class Wiedii::Controller

  get '/network/interfaces.:format' do
    objects = Wiedii::Network::Interface.getAll.sort_by(
      &Wiedii::Network::Interface::PREFERRED_ORDER
    )
    format(
      :path     => '/network/interfaces',
      :format   => params[:format],
      :objects  => objects,
      :title    => 'Network interfaces'
    )
  end

  get '/network/interfaces/:ifname.:format' do
    format(
      :path => '/network/interfaces',
      :format => params[:format],
      :title    => "Network interfaces: #{params[:ifname]}",
      :objects  => Wiedii::Network::Interface.getAll.select do |iface|
        iface.name == params[:ifname] or iface.displayname == params[:ifname]
      end
    )
  end

  # An example params is found in doc/
  put '/network/interfaces.:format' do
    current_interfaces = Wiedii::Network::Interface.getAll

    params['netifs'].each_pair do |ifname, ifhash|
      interface = current_interfaces.detect {|i| i.name == ifname}
      # In browser context, a checkbox param is simply absent (null/nil) for "unchecked".
      # In (JSON) API context, we want "active": false to be explicit, before bringing a network interface down!
      interface.modify_from_HTTP_request(ifhash, :safe_updown => (params[:format] != 'html'))
    end

    updated_objects = Wiedii::Network::Interface.getAll.sort_by(
        &Wiedii::Network::Interface::PREFERRED_ORDER
    )

    format(
      :path     => '/network/interfaces',
      :format   => params[:format],
      :title    => 'Network Interfaces',
      :objects  => updated_objects
    )
  end

  put '/network/interfaces/:ifname.:format' do
    ifname = params[:ifname]
    current_interface = Wiedii::Network::Interface.getAll.detect do |iface|
      iface.name == ifname
    end

    begin
      current_interface.modify_from_HTTP_request params['netifs'][ifname]
    rescue NoMethodError # in case of nil, skip!
    end

    format(
      :path     => '/network/interfaces',
      :format   => params[:format],
      :title    => "Network interfaces: #{ifname}",
      :objects  => Wiedii::Network::Interface.getAll.select do |iface|
        iface.name == ifname
      end
    )
  end

end
