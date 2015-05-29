require "assisted_workflow/exceptions"
require "assisted_workflow/addons/base"
require 'jiralicious'

# wrapper class to pivotal api client
module AssistedWorkflow::Addons
  
  # adapter class to map jira issue attributes for the required interface
  class JiraStory < SimpleDelegator
    
    def initialize(issue)
      super
      @issue = issue
    end
    
    def id
      @issue.jira_key
    end
    
    def name
      @issue.summary
    end
    
    def current_state
      @issue.fields.current["status"]["name"]
    end

    def owners_str
      @issue.fields.current["assignee"]["name"]
    end
    
    def estimate
      @issue.fields.current["priority"]["name"]
    end
  end
  
  class Jira < Base
    required_options :username, :password, :uri, :project, :unstarted, :started, :finished
  
    def initialize(output, options = {})
      super
      Jiralicious.configure do |config|
        config.username = options["username"]
        config.password = options["password"]
        config.uri = options["uri"]
        config.api_version = "latest"
        config.auth_type = :basic
      end
      @project = options["project"]
      @username = options["username"]
      @unstarted = options["unstarted"]
      @started = options["started"]
      @finished = options["finished"]
    end
    
    def find_story(story_id)
      if !story_id.nil?
        log "loading story ##{story_id}"
        issue = Jiralicious::Issue.find(story_id)
        story = JiraStory.new(issue) if issue
        story
      end
    end
  
    def start_story(story, options = {})
      log "starting story ##{story.id}"
      move_story! story, @started
    end
  
    def finish_story(story, options = {})
      log "finishing story ##{story.id}"
      move_story! story, @finished
      story.comments.add(options[:note]) if options[:note]
    end
  
    def pending_stories(options = {})
      log "loading pending stories"
      states = [@unstarted]
      states << @started if options[:include_started]
      query = "project=#{@project} and assignee='#{@username}' and status in ('#{states.join("','")}')"
      response = Jiralicious.search(query, :max_results => 5)
      log "loading stories info"
      response.issues_raw.map do |issue|
        JiraStory.new(Jiralicious::Issue.new(issue))
      end
    end
    
    def valid?
      !@project.nil?
    end
  
    private
  
    def move_story!(story, status)
      url = "#{Jiralicious.rest_path}/issue/#{story.id}/transitions"
      transitions = Jiralicious::Issue.get_transitions(url)
      transition = transitions.parsed_response["transitions"].find{|t| t["to"]["name"] == status}
      if transition
        Jiralicious::Issue.transition(url, {"transition" => transition["id"]})
      else
        raise AssistedWorkflow::Error, "cannot find a valid transition to move the story to #{status}"
      end
    end
  end
end
