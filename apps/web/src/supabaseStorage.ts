import { supabase } from "./supabase";

const bucketName = "dashboard-evidence";
const maxImageSize = 10 * 1024 * 1024;
const supportedImageTypes = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif",
]);

export interface UploadedDashboardImage {
  path: string;
  signedUrl: string;
}

export async function uploadDashboardImage(
  file: File,
): Promise<UploadedDashboardImage> {
  if (!supabase) throw new Error("Supabase is not configured.");
  if (!supportedImageTypes.has(file.type)) {
    throw new Error("Choose a JPEG, PNG, WebP, or GIF image.");
  }
  if (file.size > maxImageSize) {
    throw new Error("Images must be 10 MB or smaller.");
  }

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();
  if (userError) {
    throw new Error(`Could not verify your session: ${userError.message}`);
  }
  if (!user) throw new Error("Your session has expired. Sign in again.");

  const extension = file.type.split("/")[1].replace("jpeg", "jpg");
  const path = `${user.id}/${crypto.randomUUID()}.${extension}`;
  const bucket = supabase.storage.from(bucketName);
  const { error: uploadError } = await bucket.upload(path, file, {
    contentType: file.type,
    upsert: false,
  });
  if (uploadError) {
    throw new Error(`Could not upload image to Supabase: ${uploadError.message}`);
  }

  const { data, error: signingError } = await bucket.createSignedUrl(path, 3600);
  if (signingError || !data?.signedUrl) {
    const { error: cleanupError } = await bucket.remove([path]);
    const cleanupMessage = cleanupError
      ? ` The uploaded file could not be removed: ${cleanupError.message}`
      : "";
    throw new Error(
      `Could not create a private image link: ${signingError?.message ?? "No signed URL was returned."}${cleanupMessage}`,
    );
  }

  return { path, signedUrl: data.signedUrl };
}

export async function signDashboardImage(
  path: string,
): Promise<{ signedUrl?: string; error?: string }> {
  if (!supabase) throw new Error("Supabase is not configured.");
  const { data, error } = await supabase.storage
    .from(bucketName)
    .createSignedUrl(path, 3600);
  if (error) return { error: error.message };
  if (!data?.signedUrl) {
    return { error: "No signed URL was returned by Supabase Storage." };
  }
  return { signedUrl: data.signedUrl };
}
