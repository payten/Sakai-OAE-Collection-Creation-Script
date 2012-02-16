#!/usr/bin/env jruby

require 'net/http'
require 'rubygems'
require 'json'

@userids = []
if ARGV.size === 1
  userids_file = username = ARGV[0]
  File.open(userids_file, "r") { |f|
      while line = f.gets  
        userid = line.strip
        @userids.push(userid) unless userid.empty?
      end
  }
else
  @userids = ["payten"]
end

puts @userids

#######################################
# Script Customisations!
#


@url = URI.parse("http://localhost:8080")

@user = "admin"
@pass = "admin"


# users to create collection for


# collection details
@collection_title = "LS Portfolio"
@collection_access = "private" # public | everyone | private

# collection skin
# NB. that if you set this value, then you will need the following patch 
# to display skins for pooled content items: https://github.com/payten/3akai-ux/tree/customstylesforcontent
# 
@collection_skin = "/dev/skins/nyu/nyu.liberalstudies.skin.css"

# content to add to new collection
# if you want to set a skin (like above) include a "skin" along with "title" and "description"
@default_content = [
	{
		"title" => "About My LS Portfolio",
		"content" => "<p>All Global Liberal Studies students use a dynamic ATLAS Portfolio throughout their four years in the program to save and organize material from their courses, internships, experiential learning placements, and global experiences. Among other benefits, this Portfolio will help you choose your concentration and aid in the construction of your Senior Thesis.</p><p>Your Portfolio uses the Collections feature in the ATLAS Network. You can simply drag and drop material from your courses in ATLAS or from your computer into the Portfolio collection and add notes in the details box of the content profile for each piece. You can also make smaller collections of items within your main Portfolio Collection.</p><p>Your Liberal Studies Portfolio is intended to be shared with your advisors and professors to help them get a sense of your interests and development; it extends education beyond and across classes. Your ATLAS personal Library (accessible from your Dashboard) gives you a place for private storage.</p><p>For help with ATLAS, check out the <a href='http://www.nyu.edu/cgi-bin/its/askits/kbasesearch.pl?terms=ATLAS&terms=nyuhome&results=self&submit=Search'>NYU ITS ATLAS support page</a>. Or email Lucy Appert (<a href='mailto:lucy.appert@nyu.edu'>lucy.appert@nyu.edu</a>) or Jen San Miguel (<a href='mailto:jen.sanmiguel@nyu.edu'>jen.sanmiguel@nyu.edu</a>).</p>" 
	}
]



#######################################
# Script Stuff
#

def get(path)
  Net::HTTP.start(@url.host, @url.port) do |http|
	#print "-- GET: #{path}\n"
      req = Net::HTTP::Get.new(path)
      req.basic_auth @user, @pass
      return http.request(req)
  end
end

def get_json(path, raw = false)
    Net::HTTP.start(@url.host, @url.port) do |http|
		#print "-- GET: #{path}\n"
        req = Net::HTTP::Get.new(path)
        req.basic_auth @user, @pass
        response = http.request(req)

        if raw
            return response.body()
        else
            return JSON.parse(response.body())
        end
    end
end


def post_json(path, json)
    prim_post(path, {
		  ":content" => json,
		  ":operation" => "import",
		  ":replace" => "true",
		  ":replaceProperties" => "true",
		  ":contentType" => "json"
	})
end

def prim_post(path, formData) 
	Net::HTTP.start(@url.host, @url.port) do |http|
        req = Net::HTTP::Post.new(path)
        req.basic_auth @user, @pass
		req.add_field("Referer", "#{@url.to_s}/dev")
        req.set_form_data(formData)

        return http.request(req)
    end
end

def post_batch(requests)
    Net::HTTP.start(@url.host, @url.port) do |http|
        req = Net::HTTP::Post.new("/system/batch")
        req.basic_auth @user, @pass
		req.add_field("Referer", "#{@url.to_s}/dev")	
        req.set_form_data({"requests" => JSON.generate(requests)})

        return http.request(req)
    end
end


def generateWidgetId()
	"id" + (1_000_000 + rand(10_000_000 - 1_000_000)).to_s
end

def userExists(user_id) 
  print "\n ~~Checking if #{user_id} exists: "
  response = get("/~#{user_id}/public/authprofile.profile.json")
  print response
  
  if response.code === '200' then
    
     # for NYU - get the user's name for the collection title
     json = JSON.parse(response.body())
     first_name = json["basic"]["elements"]["firstName"]["value"]
     last_name = json["basic"]["elements"]["lastName"]["value"]

     @collection_title = "#{first_name} #{last_name} - #{@collection_title}"
    
    return true
  end
  false
end

def createCollection(id, user_id)
    # 1. create the base node for the collection
    # the collection data
  	formData = {
		            "_charset_" => "utf-8",
		            "mimeType" => "x-sakai/collection",
					      "sakai:copyright" => "creativecommons",
      					"sakai:description" => "",
      					"sakai:permissions" => @collection_access,                
      					"sakai:pooled-content-file-name" => @collection_title,
      					"sakai:pool-content-created-for" => user_id,
      					"sakai:showalways" => "true",
      					"sakai:showalways@TypeHint" => "Boolean",
      					"sakai:showcomments" => "true",
      					"structure0" => JSON.generate({
      						"main"=> {
      							"_ref"=> id,
      							"_order"=> 0,
      							"_title"=> @collection_title,
      							"_nonEditable"=> true,
      							"main"=> {
      								"_ref"=> id,
      								"_order"=> 0,
      								"_title"=> @collection_title,
      								"_nonEditable"=> true
      							}
      						}
      					})
            }
		
	if @collection_skin then
		formData["sakai:customStyle"] = @collection_skin
	end
		
	# POST to createfile
    response = prim_post("/system/pool/createfile", formData)
    json = JSON.parse(response.body())	
    content_id = json["_contentItem"]["poolId"]
    print "\n~~ create collection '#{@collection_title}' content page #{content_id}: "
    print response
	
	# Ensure creator is set as user!
	# set filename and link access
	requests = [
		{
			"url"=>"/p/#{content_id}","method"=>"POST","parameters"=>{
				"sakai:pool-content-created-for" => user_id
			}
		}
	]
	response = post_batch(requests)
	print "\n~~ batch update creator for collection: "
    print response	
	
    return content_id
end

def setAccessOnCollection(collection_id)
  # 3. Batch set the permissions on the pooled content item
  if @collection_access === "everyone" then
	  requests = [
					{"url"=>"/p/#{collection_id}.members.html","method"=>"POST","parameters"=>{":viewer@Delete"=>"anonymous", ":viewer"=>@collection_access}},
					{"url"=>"/p/#{collection_id}.modifyAce.html","method"=>"POST","parameters"=>{"principalId"=>@collection_access,"privilege@jcr:read"=>"granted"}},
					{"url"=>"/p/#{collection_id}.modifyAce.html","method"=>"POST","parameters"=>{"principalId"=>"anonymous","privilege@jcr:read"=>"denied"}}
				 ]
  elsif @collection_access === "public" then
	  requests = [
					{"url"=>"/p/#{collection_id}.members.html","method"=>"POST","parameters"=>{":viewer"=>["everyone","anonymous"]}},
					{"url"=>"/p/#{collection_id}.modifyAce.html","method"=>"POST","parameters"=>{"principalId"=>["everyone"],"privilege@jcr:read"=>"granted"}},
					{"url"=>"/p/#{collection_id}.modifyAce.html","method"=>"POST","parameters"=>{"principalId"=>["anonymous"],"privilege@jcr:read"=>"denied"}}
				 ]
  elsif @collection_access === "private" then
	  requests = [
					{"url"=>"/p/#{collection_id}.members.html","method"=>"POST","parameters"=>{":viewer@Delete"=>["anonymous","everyone"]}},
					{"url"=>"/p/#{collection_id}.modifyAce.html","method"=>"POST","parameters"=>{"principalId"=>["everyone"],"privilege@jcr:read"=>"denied"}},
					{"url"=>"/p/#{collection_id}.modifyAce.html","method"=>"POST","parameters"=>{"principalId"=>["anonymous"],"privilege@jcr:read"=>"denied"}}
				 ]

  end
  response = post_batch(requests)
  print "\n~~ batch access: "
  print response
end

def createCollectionGroups(collection_id)
    # 4. Create the pseudoGroups
    requests = []
    group_id = "c-"+collection_id
    # 4a. Create the collection managers group 
    requests.push({
          "url" => "/system/userManager/group.create.json",
          "method" => "POST",
          "parameters" => {
              ":name"=> group_id+"-managers",
              "sakai:group-title"=> "",
              "sakai:roles"=> "",
              "sakai:group-id"=> group_id+"-managers",
              "sakai:category"=> "collection",
              "sakai:excludeSearch"=> true,
              "sakai:pseudoGroup"=> true,
              "sakai:pseudoGroup@TypeHint"=> "Boolean",
              "sakai:parent-group-title"=> @collection_title,
              "sakai:parent-group-id"=> group_id,
              "sakai:role-title"=> "MANAGER",
              "sakai:role-title-plural"=> "MANAGERS"
          }
    })
    # 4b. Create the collection members group
    requests.push({
          "url" => "/system/userManager/group.create.json",
          "method" => "POST",
          "parameters" => {
              ":name"=> group_id+"-members",
              "sakai:group-title"=> "",
              "sakai:roles"=> "",
              "sakai:group-id"=> group_id+"-members",
              "sakai:category"=> "collection",
              "sakai:excludeSearch"=> true,
              "sakai:pseudoGroup"=> true,
              "sakai:pseudoGroup@TypeHint"=> "Boolean",
              "sakai:parent-group-title"=> @collection_title,
              "sakai:parent-group-id"=> group_id,
              "sakai:role-title"=> "MEMBER",
              "sakai:role-title-plural"=> "MEMBERS"
          }
    })    
    # 4c. Create the main collections group
    requests.push({
          "url" => "/system/userManager/group.create.json",
          "method" => "POST",
          "parameters" => {
              ":name"=> group_id,
              "sakai:group-title"=> @collection_title,
              "sakai:roles"=> "[{\"id\":\"managers\",\"title\":\"MANAGER\",\"titlePlural\":\"MANAGERS\",\"isManagerRole\":true,\"manages\":[\"members\"]},{\"id\":\"members\",\"title\":\"MEMBER\",\"titlePlural\":\"MEMBERS\",\"isManagerRole\":false}]",
              "sakai:group-id"=> group_id,
              "sakai:category"=> "collection",
              "sakai:excludeSearch"=> true,
              "sakai:pseudoGroup"=> false,
              "sakai:pseudoGroup@TypeHint"=> "Boolean"
          }
    })    
    # 4d. Create the groups
    response = post_batch(requests)
    print "\n~~ batch pseudogroups: "
    print response
end

def shareCollectionWithManagers(collection_id, user_id)  
  group_id = "c-"+collection_id
  # 4e. Set the correct managers
  requests = [
    {"url"=>"/system/userManager/group/c-#{collection_id}-managers.update.json","method"=>"POST","parameters"=>{":manager"=>"c-#{collection_id}-managers"}},
    {"url"=>"/system/userManager/group/c-#{collection_id}-members.update.json","method"=>"POST","parameters"=>{":manager"=>"c-#{collection_id}-managers"}},
    {"url"=>"/system/userManager/group/c-#{collection_id}.update.json","method"=>"POST","parameters"=>{":manager"=>"c-#{collection_id}-managers"}}
  ]
  response = post_batch(requests)
  print "\n~~ batch manager access: "
  print response
  
  requests = [
    {"url"=>"/system/userManager/group/c-#{collection_id}-managers.update.json","method"=>"POST","parameters"=>{":member"=>user_id,":viewer"=>user_id}},
    {"url"=>"/system/userManager/group/c-#{collection_id}.update.json","method"=>"POST","parameters"=>{":member"=>"c-#{collection_id}-managers",":viewer"=>"c-#{collection_id}-managers"}},
    {"url"=>"/system/userManager/group/c-#{collection_id}.update.json","method"=>"POST","parameters"=>{":member"=>"c-#{collection_id}-members",":viewer"=>"c-#{collection_id}-members"}}
  ]
  response = post_batch(requests)
  print "\n~~ batch manager access: "
  print response
end

def shareCollectionWithMembers(collection_id, user_id)
  requests = [
    {"url"=>"/system/userManager/group/c-#{collection_id}-members.update.json","method"=>"POST","parameters"=>{":manager@Delete"=>user_id}},
    {"url"=>"/system/userManager/group/c-#{collection_id}-managers.update.json","method"=>"POST","parameters"=>{":manager@Delete"=>user_id}},
    {"url"=>"/system/userManager/group/c-#{collection_id}.update.json","method"=>"POST","parameters"=>{":manager@Delete"=>user_id}}
  ]
  response = post_batch(requests)
  print "\n~~ batch member access: "
  print response  
end

def setCollectionGroupAccess(collection_id)
	if @collection_access === "everyone" then
		requests = 	[
			{"url"=>"/system/userManager/group/c-#{collection_id}-managers.update.html","method"=>"POST","parameters"=>{":viewer"=>"everyone",":viewer@Delete"=>"anonymous","sakai:group-visible"=>"logged-in-only","sakai:group-joinable"=>"yes"}},
			{"url"=>"/system/userManager/group/c-#{collection_id}-members.update.html","method"=>"POST","parameters"=>{":viewer"=>"everyone",":viewer@Delete"=>"anonymous","sakai:group-visible"=>"logged-in-only","sakai:group-joinable"=>"yes"}},
			{"url"=>"/system/userManager/group/c-#{collection_id}.update.html","method"=>"POST","parameters"=>{":viewer"=>"everyone",":viewer@Delete"=>"anonymous","sakai:group-visible"=>"logged-in-only","sakai:group-joinable"=>"yes"}}
		]
	elsif @collection_access === "public" then
		requests = 	[
			{"url"=>"/system/userManager/group/c-#{collection_id}-managers.update.html","method"=>"POST","parameters"=>{":viewer"=>["everyone","anonymous"],"sakai:group-visible"=>"public","sakai:group-joinable"=>"yes"}},
			{"url"=>"/system/userManager/group/c-#{collection_id}-members.update.html","method"=>"POST","parameters"=>{":viewer"=>["everyone","anonymous"],"sakai:group-visible"=>"public","sakai:group-joinable"=>"yes"}},
			{"url"=>"/system/userManager/group/c-#{collection_id}.update.html","method"=>"POST","parameters"=>{":viewer"=>["everyone","anonymous"],"sakai:group-visible"=>"public","sakai:group-joinable"=>"yes"}}
		]
	elsif @collection_access === "private" then
		requests = 	[
			{"url"=>"/system/userManager/group/c-#{collection_id}-managers.update.html","method"=>"POST","parameters"=>{":viewer"=>"c-#{collection_id}",":viewer@Delete"=>["everyone","anonymous"],"sakai:group-visible"=>"members-only","sakai:group-joinable"=>"yes"}},
			{"url"=>"/system/userManager/group/c-#{collection_id}-members.update.html","method"=>"POST","parameters"=>{":viewer"=>"c-#{collection_id}",":viewer@Delete"=>["everyone","anonymous"],"sakai:group-visible"=>"members-only","sakai:group-joinable"=>"yes"}},
			{"url"=>"/system/userManager/group/c-#{collection_id}.update.html","method"=>"POST","parameters"=>{":viewer"=>"c-#{collection_id}",":viewer@Delete"=>["everyone","anonymous"],"sakai:group-visible"=>"members-only","sakai:group-joinable"=>"yes"}}
		]
	end
    
  response = post_batch(requests)
  print "\n~~ batch visible to #{@collection_access}: "
  print response
end

def shareCollectionWithGroups(collection_id)
  response = prim_post("/p/#{collection_id}.members.json", {":manager"=>"c-#{collection_id}-managers"})
  print "\n~~ share with pseudo groups (managers): "
  print response
  response = prim_post("/p/#{collection_id}.members.json", {":manager"=>"c-#{collection_id}-members"})
  print "\n~~ share with pseudo groups (members): "
  print response
  # NYU only - add pseudo group to enable custom portfolio search 
  response = prim_post("/p/#{collection_id}.members.json", {":viewer"=>"g-portfolio-search"})
  print "\n~~ share with g-portfolio-search (members): "
  print response  
end

def removeCreatorAsManager(collection_id)
  # so the creator is the @user variable I think...
  response = prim_post("/p/#{collection_id}.members.json", {":manager@Delete"=>@user})
  print "\n~~ remove creator from managers: "
  print response
end

def addCollectionToLibrary(ref_id, collection_id)
  data = {
    ":content"=> JSON.generate({
                    "#{ref_id}" => {"page" => "<img id='widget_collectionviewer_#{ref_id}2' class='widget_inline' src='/devwidgets/mylibrary/images/mylibrary.png'/></p>"},
                    "#{ref_id}2" => {"collectionviewer" => {"groupid" => "c-#{collection_id}"}}
                 }),
    ":contentType"=> "json",
    ":operation"=> "import",
    ":replace"=> true,
    ":replaceProperties"=> true
  }
  
  response = prim_post("/p/#{collection_id}", data)
  print "\n~~ add to library: "
  print response
end


# 
# About this Page related functions
#

def	createAndAddContent(content_data, index, user_id, collection_id)
  # create the content
  ref_id = generateWidgetId()
  
  title = content_data["title"]
  content = content_data["content"]
  
  print "\n~* creating the content page '#{title}' for the collection..."
  
  data = {
    "mimeType" =>	"x-sakai/document",
    "structure0" =>	JSON.generate({"page1"=>{"_ref"=>ref_id,"_order"=>index,"_title"=>title,"main"=> {"_ref"=>ref_id,"_order"=>index,"_title"=>title}}})
  }
  response = prim_post("/system/pool/createfile", data)
  json = JSON.parse(response.body())
  content_id = json["_contentItem"]["poolId"]
  
  print "\n~* '#{title}' has a content id of #{content_id} "
  
  
  # set the content
  data = {
    ":content"=> JSON.generate({
                    "#{ref_id}" => {"page" =>content}
                 }),
    ":contentType"=> "json",
    ":operation"=> "import",
    ":replace"=> true,
    ":replaceProperties"=> true
  }
  
  response = prim_post("/p/#{content_id}", data)  
  print "\n~~ set content for '#{title}': "
  print response
    
  # set filename and link access
  requests = [
     {"url"=>"/p/#{content_id}","method"=>"POST","parameters"=>{
          "sakai:pooled-content-file-name"=>title,
  		    "sakai:pool-content-created-for" => user_id,
          "sakai:description"=>"",
          "sakai:permissions"=>@collection_access,
          "sakai:copyright"=>"creativecommons",
          "sakai:allowcomments"=>"true",
          "sakai:showcomments"=>"true"
        }
    }
  ]
  
  if content_data.has_key?("skin") then
    requests[0]["parameters"]["sakai:customStyle"] = content_data["skin"]
	end
  
  response = post_batch(requests)
  print "\n~~ batch access for '#{title}': "
  print response
  
  # set access
  if @collection_access === "everyone" then
		requests = [
			{"url"=>"/p/#{content_id}.members.html","method"=>"POST","parameters"=>{":viewer@Delete"=>"anonymous", ":viewer"=>@collection_access}},
			{"url"=>"/p/#{content_id}.modifyAce.html","method"=>"POST","parameters"=>{"principalId"=>@collection_access,"privilege@jcr:read"=>"granted"}},
			{"url"=>"/p/#{content_id}.modifyAce.html","method"=>"POST","parameters"=>{"principalId"=>"anonymous","privilege@jcr:read"=>"denied"}},
			{"url"=>"/p/#{content_id}.members.json","method"=>"POST","parameters"=>{":manager@Delete"=>@user}},    
			{"url"=>"/p/#{content_id}.members.json","method"=>"POST","parameters"=>{":manager"=>user_id,":viewer@Delete"=>user_id}}
		]
  elsif @collection_access === "public" then
		requests = [
			{"url"=>"/p/#{content_id}.members.html","method"=>"POST","parameters"=>{":viewer"=>["everyone","anonymous"]}},
			{"url"=>"/p/#{content_id}.modifyAce.html","method"=>"POST","parameters"=>{"principalId"=>["everyone"],"privilege@jcr:read"=>"granted"}},
			{"url"=>"/p/#{content_id}.modifyAce.html","method"=>"POST","parameters"=>{"principalId"=>["anonymous"],"privilege@jcr:read"=>"granted"}},
			{"url"=>"/p/#{content_id}.members.json","method"=>"POST","parameters"=>{":manager"=>user_id,":manager@Delete"=>@user}}
		]
  elsif @collection_access === "private" then
		requests = [
			{"url"=>"/p/#{content_id}.members.html","method"=>"POST","parameters"=>{":viewer@Delete"=>["anonymous","everyone"]}},
			{"url"=>"/p/#{content_id}.modifyAce.html","method"=>"POST","parameters"=>{"principalId"=>["everyone"],"privilege@jcr:read"=>"denied"}},
			{"url"=>"/p/#{content_id}.modifyAce.html","method"=>"POST","parameters"=>{"principalId"=>["anonymous"],"privilege@jcr:read"=>"denied"}},
			{"url"=>"/p/#{content_id}.members.json","method"=>"POST","parameters"=>{":manager"=>user_id,":manager@Delete"=>@user}}
		]

  end    
  response = post_batch(requests)
  print "\n~~ batch access (again) for '#{title}': "
  print response
  
  # add to collection
  prim_post("/p/#{content_id}.members.html", {":viewer"=>"c-#{collection_id}"})
  print "\n~~ add '#{title}' to collection: "
  print response  
end



#######################################
# The method that does all the stuff
#

def do_stuff
  @userids.each do |user_id|
  	print "\n\n~* creating collection for #{user_id}..."
  	# check user exists
    unless userExists(user_id) then
      print "\n~**** User #{user_id} doesn't exist!!!\n"
      next;
    end
    # create the collection etc
    ref_id = generateWidgetId()
	print "\n~* collection widget id = #{ref_id}"
    collection_id = createCollection(ref_id, user_id)
	print "\n~* collection content id = #{collection_id}"
    setAccessOnCollection(collection_id)
    createCollectionGroups(collection_id)
    shareCollectionWithManagers(collection_id, user_id) 
    shareCollectionWithMembers(collection_id, user_id)
	setCollectionGroupAccess(collection_id)
    shareCollectionWithGroups(collection_id)
    removeCreatorAsManager(collection_id)
    addCollectionToLibrary(ref_id, collection_id)
    
    # add any default content to the collection
	@default_content.each_with_index do | content_data, i |
		createAndAddContent(content_data, i, user_id, collection_id)
	end

    print "\n"
  end
end


do_stuff
