class Book
  include Mongoid::Document
  field :user_id, :type => Integer
  field :path, :type => String
  field :title, :type => String
  field :blurb, :type => String
  field :permalink, :type => String
  field :current_commit, :type => String
  field :just_added, :type => Boolean, :default => true
  field :processing, :type => Boolean, :default => false
  field :notes_count, :type => Integer, :default => 0
  field :hidden, :type => Boolean, :default => false
  
  embeds_many :chapters
  
  @queue = "normal"
  before_create :set_permalink
  after_create :enqueue
  
  def self.perform(id)
    book = Book.find(id)
    # TODO: determine if path is HTTP || Git
    # TODO: determine if path is public
    user, repo = book.path.split("/")[-2, 2]
    git = Git.new(user, repo)
    book.path = git.path.to_s
    current_commit = git.current_commit rescue nil
    git.update!

    book.manifest do |files|
      files.each do |file|
        Chapter.process!(book, git, file)
      end
    end

    # When done, update the book with the current commit as a point of reference
    book.current_commit = git.current_commit
    book.processing = false
    book.just_added = false
    book.save
  end

  def manifest(&block)
    Dir.chdir(path) do
      if File.exist?("manifest.txt")
        files = File.read("manifest.txt").split("\n")
        if block_given?
          yield(files)
        else
          files
        end
      else
        raise "Couldn't find manifest.txt"
      end
    end
  end

  def notes
    chapters.map(&:notes).flatten
  end

  def to_param
    permalink
  end

  def enqueue
    Resque.enqueue(self.class, self.id)
    self.processing = true
    self.save!
  end

  def set_permalink
    self.permalink = title.parameterize
  end
end
