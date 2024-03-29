require 'sinatra/base'

require 'wiedii/network/iptables'

class Wiedii::Controller

  get '/network/nat/masquerade.:format' do
    redirect "/network/nat/snat.#{params[:format]}"
  end

  get '/network/nat/snat.:format' do
    iptablesobj = Wiedii::Network::Iptables.new(
      :ip_version => '4', # no IPv6 NAT implemented (probably useless...)
      :tables => %w{nat}
    )
    iptablesobj.get_all_info

    format(
      :path => '/network/nat/snat',
      :format => params[:format],
      :objects  => iptablesobj,
      :title => 'SNAT'
    )
  end

  put '/network/nat/snat.:format' do
    # let's *write* into params... looks strange, but it's useful :-)
    params['version'] = '4'   # IPv4
    params['table']   = 'nat'

    msg = Wiedii::Network::Iptables.add_rule_from_HTTP_request(params) if
      params['add_rule']
    msg = Wiedii::Network::Iptables.del_rule_from_HTTP_request(params) if
      params['del_rule']
    msg = Wiedii::Network::Iptables.move_rule_up_from_HTTP_request(params) if
      params['move_rule_up']
    msg = Wiedii::Network::Iptables.move_rule_down_from_HTTP_request(params) if
      params['move_rule_down']
    if msg.respond_to? :[]
      # taken from routing.rb
      unless msg[:ok] # TODO: always sure the error is client-side?
        status(409)   # TODO: what is the most appropriate HTTP response in this                      # case? 400 Bad Request? 409 Conflict?
        #headers("X-STDERR" => msg[:stderr].strip.gsub("\n","\\n"))
      end
    end

    iptablesobj = Wiedii::Network::Iptables.new(
      :ip_version => params[:version],
      :tables => %w{nat}
    )
    iptablesobj.get_all_info

    format(
      :path => '/network/nat/snat',
      :format => params[:format],
      :objects  => iptablesobj,
      :msg  => msg,
      :title => 'SNAT'
    )
  end

end
