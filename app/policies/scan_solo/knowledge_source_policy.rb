class ScanSolo::KnowledgeSourcePolicy < ScanSolo::ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def update?
    true
  end

  def destroy?
    true
  end

  def reindex?
    update?
  end

  def retrieval_tests?
    index?
  end
end
