class ContainerLabelTagMapping < ApplicationRecord
  # A mapping matches labels on `resource_type` (NULL means any), `name` (required),
  # and `value` (NULL means any).
  #
  # Different labels might map to same tag, and one label might map to multiple tags.
  #
  # There are 2 kinds of rows:
  # - When `label_value` is specified, we map only this value to a specific `tag`.
  # - When `label_value` is NULL, we map this name with any value to per-value tags.
  #   In this case, `tag` specifies the category under which to create
  #   the value-specific tag (and classification) on demand.
  #
  # All involved tags must also have a Classification.

  belongs_to :tag

  require_nested :Mapper

  # Return ContainerLabelTagMapping::Mapper instance that holds current mappings,
  # can compute applicable tags, and create/find Tag records.
  def self.mapper
    ContainerLabelTagMapping::Mapper.new(in_my_region.all)
  end

  # Assigning/unassigning should be possible without Mapper instance, perhaps in another process.

  # Checks whether a Tag record is under mapping control.
  # TODO: expensive.
  def self.controls_tag?(tag)
    return false unless tag.classification.try(:read_only) # never touch user-assignable tags.
    tag_ids = [tag.id, tag.category.tag_id].uniq
    where(:tag_id => tag_ids).any?
  end

  # Assign/unassign mapping-controlled tags, preserving user-assigned tags.
  # All tag references must have been resolved first by Mapper#find_or_create_tags.
  def self.retag_entity(entity, tag_references)
    mapped_tags = Mapper.references_to_tags(tag_references)
    existing_tags = entity.tags
    Tagging.transaction do
      (mapped_tags - existing_tags).each do |tag|
        Tagging.create!(:taggable => entity, :tag => tag)
      end
      (existing_tags - mapped_tags).select { |tag| controls_tag?(tag) }.tap do |tags|
        Tagging.where(:taggable => entity, :tag => tags.collect(&:id)).destroy_all
      end
    end
    entity.tags.reset
  end
end
