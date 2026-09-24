class ScanSolo::ApplicationPolicy
  attr_reader :user_context, :user, :account, :account_user, :record

  def initialize(user_context, record)
    @user_context = user_context
    @user = user_context[:user]
    @account = user_context[:account]
    @account_user = user_context[:account_user]
    @record = record
  end

  def administrator?
    account_user&.administrator? == true
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  class Scope
    attr_reader :user_context, :user, :account, :account_user, :scope

    def initialize(user_context, scope)
      @user_context = user_context
      @user = user_context[:user]
      @account = user_context[:account]
      @account_user = user_context[:account_user]
      @scope = scope
    end

    def resolve
      scope.none
    end
  end
end
