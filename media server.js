const cloudinary = require('cloudinary').v2;

function cloudinaryConfigured() {
  return Boolean(
    process.env.CLOUDINARY_CLOUD_NAME &&
      process.env.CLOUDINARY_API_KEY &&
      process.env.CLOUDINARY_API_SECRET
  );
}

function configureCloudinary() {
  cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET,
    secure: true,
  });
}

function uploadBuffer(buffer, { folder, originalName }) {
  return new Promise((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(
      {
        folder,
        resource_type: 'image',
        filename_override: originalName,
        use_filename: true,
        unique_filename: true,
      },
      (error, result) => {
        if (error) return reject(error);
        resolve(result);
      }
    );

    stream.end(buffer);
  });
}

function registerMediaRoutes(app, { requireAuth, requireSystemAdmin, upload }) {
  configureCloudinary();

  app.post('/media/upload', requireAuth, upload.single('image'), async (req, res) => {
    if (!cloudinaryConfigured()) {
      return res.status(503).json({
        error: 'Cloudinary is not configured. Set CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, and CLOUDINARY_API_SECRET.',
      });
    }

    if (!req.file || !req.file.buffer) {
      return res.status(400).json({ error: 'An image file is required' });
    }

    const mime = (req.file.mimetype || '').toLowerCase();
    if (!mime.startsWith('image/')) {
      return res.status(400).json({ error: 'Only image uploads are allowed' });
    }

    try {
      const folders = {
        support: 'edupal/support',
        notifications: 'edupal/notifications',
        profiles: 'edupal/profiles',
      };
      const folderKey = String(req.body?.folder || 'support').toLowerCase();
      const folder = folders[folderKey] || folders.support;

      const result = await uploadBuffer(req.file.buffer, {
        folder,
        originalName: req.file.originalname,
      });

      res.json({
        url: result.secure_url,
        publicId: result.public_id,
        width: result.width,
        height: result.height,
        format: result.format,
      });
    } catch (err) {
      console.error('Cloudinary upload failed:', err.message);
      res.status(500).json({ error: 'Image upload failed' });
    }
  });

  app.post('/media/delete', requireAuth, async (req, res) => {
    if (!cloudinaryConfigured()) {
      return res.status(503).json({ error: 'Cloudinary is not configured' });
    }

    const publicId = typeof req.body?.publicId === 'string' ? req.body.publicId.trim() : '';
    if (!publicId) {
      return res.status(400).json({ error: 'A Cloudinary publicId is required' });
    }

    // Only allow deleting assets this app uploaded.
    if (!publicId.startsWith('edupal/')) {
      return res.status(403).json({ error: 'You can only delete Edupal media' });
    }

    try {
      await destroyEdupalImage(publicId);
      res.json({ deleted: true });
    } catch (err) {
      console.error('Cloudinary delete failed:', err.message);
      res.status(500).json({ error: 'Image delete failed' });
    }
  });
}

async function destroyEdupalImage(publicId) {
  configureCloudinary();
  if (!cloudinaryConfigured()) {
    throw new Error('Cloudinary is not configured');
  }
  const id = typeof publicId === 'string' ? publicId.trim() : '';
  if (!id) {
    throw new Error('A Cloudinary publicId is required');
  }
  if (!id.startsWith('edupal/')) {
    throw new Error('You can only delete Edupal media');
  }
  await cloudinary.uploader.destroy(id, { resource_type: 'image' });
}

function profileAvatarPublicId(profile) {
  const stored = String(profile?.avatar_public_id || '').trim();
  if (stored) return stored;

  const url = String(profile?.avatar_url || '').trim();
  if (!url.includes('res.cloudinary.com') || !url.includes('/edupal/')) {
    return '';
  }
  const match = url.match(/\/upload\/(?:v\d+\/)?(.+?)(?:\.[a-z0-9]+)?(?:\?.*)?$/i);
  return match ? match[1] : '';
}

async function deleteProfileAvatar(profile) {
  const publicId = profileAvatarPublicId(profile);
  if (!publicId) return false;
  try {
    await destroyEdupalImage(publicId);
    return true;
  } catch (err) {
    console.warn('Profile avatar Cloudinary cleanup failed:', err.message);
    return false;
  }
}

module.exports = {
  registerMediaRoutes,
  deleteProfileAvatar,
};
