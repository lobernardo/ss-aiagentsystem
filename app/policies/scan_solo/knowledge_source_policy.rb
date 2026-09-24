class ScanSolo::KnowledgeSourcePolicy < ScanSolo::ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    administrator?
  end

  def update?
    administrator?
  end

  def destroy?
    administrator?
  end

  def reindex?
    update?
  end

  def retrieval_tests?
    administrator?
  end
end
