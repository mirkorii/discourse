class AnonymousShadowCreator

  def self.get_master(user)
    return unless user
    return if !SiteSetting.allow_anonymous_posting

    if (master_id = user.custom_fields["master_id"].to_i) > 0
      User.find_by(id: master_id)
    end

  end

  def self.get(user)
    return unless user
    return if !SiteSetting.allow_anonymous_posting ||
       user.trust_level < SiteSetting.anonymous_posting_min_trust_level

    if (shadow_id = user.custom_fields["shadow_id"].to_i) > 0
      shadow = User.find_by(id: shadow_id)

      if shadow && shadow.post_count > 0 &&
          shadow.last_posted_at < SiteSetting.anonymous_account_duration_minutes.minutes.ago
        shadow = nil
      end

      shadow || create_shadow(user)
    else
      create_shadow(user)
    end
  end

  def self.create_shadow(user)
    User.transaction do
      shadow = User.create!(
        password: SecureRandom.hex,
        email: "#{SecureRandom.hex}@#{SecureRandom.hex}.com",
        name: "",
        username: UserNameSuggester.suggest(I18n.t(:anonymous).downcase),
        active: true,
        trust_level: 1,
        trust_level_locked: true,
        email_private_messages: false,
        email_digests: false,
        created_at: 1.day.ago # bypass new user restrictions
      )

      shadow.email_tokens.update_all  confirmed: true
      shadow.activate


      # can not hold dupes
      UserCustomField.where(user_id: user.id,
                            name: "shadow_id").destroy_all

      UserCustomField.create!(user_id: user.id,
                              name: "shadow_id",
                              value: shadow.id)

      UserCustomField.create!(user_id: shadow.id,
                              name: "master_id",
                              value: user.id)

      shadow.reload
      user.reload

      shadow

    end
  end
end
