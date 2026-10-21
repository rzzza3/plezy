import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../services/plex_client.dart';
import 'metadata_edit_models.dart';
import 'plex_metadata_edit_adapter.dart';

MetadataEditAdapter? metadataEditAdapterFor(MediaServerClient client) {
  if (client is PlexClient) return PlexMetadataEditAdapter(client);
  return null;
}

bool supportsMetadataEdit(MediaServerClient? client, MediaKind? kind) {
  if (client == null || kind == null || !client.capabilities.richMetadataEdit) return false;
  return metadataEditAdapterFor(client)?.supportsKind(kind) ?? false;
}
