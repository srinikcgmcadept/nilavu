class CloudBooksController < ApplicationController
  respond_to :html, :js
  include Packable

  
  def index
    cloud_books = current_user.cloud_books
    if cloud_books.any?
      add_breadcrumb "Cloud_books", cloud_books_path      
      @nodes = FindNodesByEmail.perform
      if @nodes.class == Megam::Error
        redirect_to new_cloud_book_path, :gflash => { :warning => { :value => "#{@nodes.some_msg[:msg]}", :sticky => false, :nodom_wrap => true } }
      else
        book_names = cloud_books.map {|c| c.name}
        grouped = book_names.inject({}) do |base, b| #the grouped has a short_name/Megam::Nodes collection
          group = @nodes.select{|n| n.node_name =~ /^#{b}/}
          base[b] ||= []
          base[b] << group
          base
        end        
        @launched_books = Hash[grouped.map {|key, value| [key, value.flatten.map {|vn| vn.node_name}]}]
        @launched_books_quota = @nodes.all_nodes.length        
      end
    else
      redirect_to new_cloud_book_path
    end
  end

  def build_request
   logger.debug "--> CloudBooks:Build_request, #{params}"
   packed_parms = packed("Meat::Defns",params)      
    @defnd_out ={}
    defnd_result =  CreateDefnRequests.send(params[:book_type].downcase.to_sym, packed_parms)    
    @defnd_out[:error] = "Sorry Something Wrong. Please contact #{ActionController::Base.helpers.link_to 'Our Support !.', "http://support.megam.co/"}." if @req.class == Megam::Error
    @defnd_out[:success] = defnd_result.some_msg[:msg] 
    respond_to do |format|
      format.js {
        respond_with(@defnd_out, :layout => !request.xhr? )
      }
    end
  end

  def get_request
    logger.debug "--> CloudBooks:get_request"   
   packed_parms = packed_h("Meat::Defns",params)   
   logger.debug "--> CloudBooks:get_request, #{params}"
   defns_result =  FindDefnById.send(params[:book_type], packed_parms) 
   params[:lc_apply] =  defns_result.lookup(params[:defns_id]).appdefns[:runtime_exec] unless defns_result.class == Megam::Error
    logger.debug "--> CloudBooks:get_request, #{params[:lc_apply]}"
    if params[:lc_apply]["#[start]"].present? 
         params[:lc_apply]["#[start]"] = params[:req_type]               
    end          
    packed_parms = packed("Meat::Defns",params) 
      @req_type = params[:req_type]
      @node_name = params[:node_name]  
      @appdefns_id = params[:defns_id]
      @lc_apply = params[:lc_apply]
      @book_type = params[:book_type]
   respond_to do |format|
      format.js {
        respond_with(@book_type, @lc_apply, @req_type, @node_name, @appdefns_id, :layout => !request.xhr? )
      }
   end
  end

  def send_request 
    logger.debug "--> CloudBooks:send_request"      
    packed_parms = packed_h("Meat::Defns",params)    
    defns_result =  FindDefnById.send(params[:book_type], packed_parms)  
    params[:lc_apply] =  defns_result.lookup(params[:defns_id]).appdefns[:runtime_exec] unless defns_result.class == Megam::Error
    if params[:lc_apply]["#[start]"].present? 
         params[:lc_apply]["#[start]"] = params[:req_type]
    end           
    packed_parms = packed("Meat::Defns",params)      
    @defnd_out ={}
    defnd_result =  CreateDefnRequests.send(params[:book_type].downcase.to_sym, packed_parms)    
    @defnd_out[:error] = "Sorry Something Wrong. Please contact #{ActionController::Base.helpers.link_to 'Our Support !.', "http://support.megam.co/"}." if @req.class == Megam::Error
    @defnd_out[:success] = defnd_result.some_msg[:msg] 
    respond_to do |format|
      format.js {
        respond_with(@defnd_out, :layout => !request.xhr? )
      }
    end
  end

  def clone_start
    wparams = { :node => "#{params[:clone_name]}" }
    @clone_nodes =  FindNodeByName.perform(wparams)
    logger.debug "CloudBooks:clone_start, found the node"
    
    if @clone_nodes.class == Megam::Error
      @res_msg="Sorry Something Wrong. Please contact #{ActionController::Base.helpers.link_to 'Our Support !.', "http://support.megam.co/"}."
      respond_to do |format|
        format.js {
          respond_with(@res_msg, :layout => !request.xhr? )
        }
      end
    else
      @clone_node = @clone_nodes.lookup("#{params[:clone_name]}")
      node_hash = {
        "node_name" => "#{params[:new_name]}",
        "node_type" => "#{@clone_node.node_type}",
        "req_type" => "#{@clone_node.request[:req_type]}",
        "noofinstances" => params[:noofinstances].to_i,
        "command" => @clone_node.request[:command],
        "predefs" => @clone_node.predefs,
        "appdefns" => {"timetokill" => "", "metered" => "", "logging" => "", "runtime_exec" => ""},
        "boltdefns" => {"username" => "", "apikey" => "", "store_name" => "", "url" => "", "prime" => "", "timetokill" => "", "metered" => "", "logging" => "", "runtime_exec" => ""},
        "appreq" => {},
        "boltreq" => {}
      }
      wparams = {:node => node_hash }
      @node = CreateNodes.perform(wparams)
      if @node.class == Megam::Error
        @res_msg="Sorry Something Wrong. Please contact #{ActionController::Base.helpers.link_to 'Our Support !.', "http://support.megam.co/"}."
        respond_to do |format|
          format.js {
            respond_with(@res_msg, :layout => !request.xhr? )
          }
        end
      else

        @book = current_user.cloud_books.create(:name => params[:new_name], :predef_name => @clone_node.predefs[:name], :book_type => @clone_node.node_type, :domain_name => params[:domain_name], :predef_cloud_name => "default" )
        @book.save
        params = {:book_name => "#{@book.name}#{@book.domain_name}", :request_id => "req_id", :status => "status"}
        @history = @book.cloud_books_histories.create(params)
        @history.save

        redirect_to cloud_books_path, :gflash => { :success => { :value => "Cloud book cloned successfully", :sticky => false, :nodom_wrap => true } }
      end
    end
  end

  def authorize_scm
    logger.debug "CloudBooks:authorize_scm, entry"
    auth_token = request.env['omniauth.auth']['credentials']['token']
    github = Github.new oauth_token: auth_token
    git_array = github.repos.all.collect { |repo| repo.clone_url }
    @repos = git_array
    render :template => "cloud_books/new", :locals => {:repos => @repos}
  end

  def new
    if current_user.onboarded_api
      @book =  current_user.cloud_books.build
      add_breadcrumb "Cloud_Books", cloud_books_path
      add_breadcrumb "New Cloud Platform Selection", new_cloud_book_path
    else
      redirect_to dashboards_path, :gflash => { :warning => { :value => "To create books, you need an API key. Click Profile, and generate a new API key", :sticky => false, :nodom_wrap => true } }
    end
  end

  def new_book
    add_breadcrumb "Cloud_Books", cloud_books_path
    add_breadcrumb "New Cloud_Platform Selection", new_cloud_book_path
    add_breadcrumb "Create", new_book_path    
    if"#{params[:deps_scm]}".strip.length != 0
      @deps_scm = "#{params[:deps_scm]}"
    elsif !"#{params[:scm]}".start_with?("select")
      @deps_scm = "#{params[:scm]}"
    end
    @deps_war = "#{params[:deps_war]}" if params[:deps_war]
    @book =  current_user.cloud_books.build
    @predef_cloud = ListPredefClouds.perform
    if @predef_cloud.class == Megam::Error
      redirect_to new_cloud_book_path, :gflash => { :warning => { :value => "#{@predef_cloud.some_msg[:msg]}", :sticky => false, :nodom_wrap => true } }
    else
      @predef_name = params[:predef_name]
      predef_options = {:predef_name => @predef_name}
      pred = FindPredefsByName.perform(predef_options)
      if pred.class == Megam::Error
        redirect_to new_cloud_book_path, :gflash => { :warning => { :value => "#{pred.some_msg[:msg]}", :sticky => false, :nodom_wrap => true } }
      else
        @predef = pred.lookup(@predef_name)
        @domain_name = ".megam.co"
        @no_of_instances=params[:no_of_instances]
      end
    end
  end

  def create
    data={:book_name => params[:cloud_book][:name], :book_type => params[:cloud_book][:book_type] , :predef_cloud_name => params[:cloud_book][:predef_cloud_name], :provider => params[:predef][:provider], :repo => 'default_chef', :provider_role => params[:predef][:provider_role], :domain_name => params[:cloud_book][:domain_name], :no_of_instances => params[:no_of_instances], :predef_name => params[:predef][:name], :deps_scm => params['deps_scm'], :deps_war => "#{params['deps_war']}", :timetokill => "#{params['timetokill']}", :metered => "#{params['monitoring']}", :logging => "#{params['logging']}", :runtime_exec => "#{params['runtime_exec']}"}
    options = {:data => data, :group => "server", :action => "create" }
    node_hash=MakeNode.perform(options)      
    if node_hash.class == Megam::Error
      @res_msg="Sorry Something Wrong. MSG : #{node_hash.some_msg[:msg]} Please contact #{ActionController::Base.helpers.link_to 'Our Support !.', "http://support.megam.co/"}."
      respond_to do |format|
        format.js {
          respond_with(@res_msg, :layout => !request.xhr? )
        }
      end
    else
      wparams = {:node => node_hash }
      @node = CreateNodes.perform(wparams)
      if @node.class == Megam::Error
        @res_msg="Sorry Something Wrong. Please contact #{ActionController::Base.helpers.link_to 'Our Support !.', "http://support.megam.co/"}."
        respond_to do |format|
          format.js {
            respond_with(@res_msg, :layout => !request.xhr? )
          }
        end
      else
        @book = current_user.cloud_books.create(params[:cloud_book])
        @book.save
        params = {:book_name => "#{@book.name}#{@book.domain_name}", :request_id => "req_id", :status => "status"}
        @history = @book.cloud_books_histories.create(params)
      @history.save
      end
    end
  end

  def show
    wparams = {:node => "#{params[:name]}" }
    #look at storing in a local session, as we are redoing it. 
    # The node json is getting heavy as well    
    @node = FindNodeByName.perform(wparams)
    logger.debug "--> CloudBooks:show, found node #{wparams[:node]}"
    if @node.class == Megam::Error
      @res_msg="We went into nirvana, finding node #{wparams[:node]}. Open up a support ticket. We'll investigate its disappearence #{ActionController::Base.helpers.link_to 'Our Support !.', "http://support.megam.co/"}."
      respond_to do |format|
        format.js {
          respond_with(@res_msg, :layout => !request.xhr? )
        }
      end
    else
      @requests = GetRequestsByNode.perform(wparams)  #no error checking for GetRequestsByNode ? 
      @book_requests =  GetDefnRequestsByNode.send(params[:book_type].downcase.to_sym, wparams)
      if @book_requests.class == Megam::Error
        @book_requests={"results" => {"req_type" => "", "create_at" => "", "lc_apply" => "", "lc_additional" => "", "lc_when" => ""}}
      end
      @cloud_book = @node.lookup("#{params[:name]}")
      respond_to do |format|
        format.js {
          respond_with(@cloud_book, @requests, @book_requests, :layout => !request.xhr? )
        }
      end
    end
  end

 
  def destroy
    @book = CloudBook.find(params[:id])
    options = {:node_name => "#{params[:name]}", :group => "server", :action => "delete" }
    node_hash=DeleteNode.perform(options)

    if node_hash.class == Megam::Error
      @res_msg="Sorry Something Wrong. Please contact #{ActionController::Base.helpers.link_to 'Our Support !.', "http://support.megam.co/"}."
    else
      options = { :req => node_hash }
      @node = CreateRequests.perform(options)
      if @node.class == Megam::Error
        @res_msg="Sorry Something Wrong. MSG : #{@node.some_msg[:msg]} Please contact #{ActionController::Base.helpers.link_to 'Our Support !.', "http://support.megam.co/"}."
      else
        a = params[:n_hash]
        count = a["#{@book.name}"].count
        if count<2
          @book.cloud_books_histories.each do |cbh|
            cbh.destroy
          end
        @book.destroy
        end
        @res_msg = "Cloud Book deleted Successfully"
      end
    end

    respond_to do |format|
      format.js {
        respond_with(@res_msg, :layout => !request.xhr? )
      }
    end
  end

end