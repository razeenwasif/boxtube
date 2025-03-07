import { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { 
  Container, 
  Box, 
  Typography, 
  Paper, 
  IconButton, 
  Button,
  List,
  ListItem,
  ListItemText,
  ListItemSecondaryAction,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Alert,
  Divider,
  Stack
} from '@mui/material';
import { 
  PlaylistPlay, 
  ArrowBack,
  Close
} from '@mui/icons-material';
import { usePlaylist } from '../contexts/PlaylistContext';

const PlaylistDetail = () => {
  const { playlistId } = useParams();
  const navigate = useNavigate();
  const { getPlaylist, removeFromPlaylist, updatePlaylist } = usePlaylist();
  
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [deleteVideoId, setDeleteVideoId] = useState(null);
  
  // Get playlist data
  const playlist = getPlaylist(playlistId);
  
  // Handle back button click
  const handleBack = () => {
    navigate('/playlists');
  };
  
  // Handle video click
  const handleVideoClick = (video) => {
    // Handle different video ID structures
    const videoId = video.id?.videoId || video.id;
    navigate(`/video/${videoId}`);
  };
  
  // Handle remove video
  const handleRemoveVideo = (videoId) => {
    removeFromPlaylist(playlistId, videoId);
    setDeleteDialogOpen(false);
    setDeleteVideoId(null);
  };
  
  // Handle delete dialog open
  const handleDeleteDialogOpen = (e, video) => {
    e.stopPropagation();
    const videoId = video.id?.videoId || video.id;
    setDeleteVideoId(videoId);
    setDeleteDialogOpen(true);
  };
  
  // Handle delete dialog close
  const handleDeleteDialogClose = () => {
    setDeleteDialogOpen(false);
    setDeleteVideoId(null);
  };
  
  // Get video thumbnail
  const getVideoThumbnail = (video) => {
    // Try different thumbnail sizes
    return video.snippet?.thumbnails?.high?.url || 
           video.snippet?.thumbnails?.medium?.url || 
           video.snippet?.thumbnails?.default?.url;
  };
  
  // If playlist doesn't exist, show error
  if (!playlist) {
    return (
      <Container maxWidth="md" sx={{ py: 4 }}>
        <Paper 
          sx={{ 
            p: 3, 
            backgroundColor: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            borderRadius: '12px'
          }}
        >
          <Typography variant="h5" color="var(--text-primary)" gutterBottom>
            Playlist not found
          </Typography>
          <Button
            startIcon={<ArrowBack />}
            onClick={handleBack}
            sx={{ 
              color: 'var(--text-secondary)',
              '&:hover': { color: 'var(--primary-color)' }
            }}
          >
            Back to Playlists
          </Button>
        </Paper>
      </Container>
    );
  }
  
  return (
    <Container maxWidth="md" sx={{ py: 4 }}>
      <Paper 
        sx={{ 
          p: 3, 
          backgroundColor: 'var(--card-bg)',
          border: '1px solid var(--border-color)',
          borderRadius: '12px'
        }}
      >
        <Stack direction="row" alignItems="center" spacing={2} sx={{ mb: 3 }}>
          <IconButton
            onClick={handleBack}
            sx={{ 
              color: 'var(--text-secondary)',
              '&:hover': { color: 'var(--primary-color)' }
            }}
          >
            <ArrowBack />
          </IconButton>
          
          <Box sx={{ flex: 1 }}>
            <Typography variant="h4" color="var(--text-primary)" sx={{ fontWeight: 500 }}>
              {playlist.name}
            </Typography>
            {playlist.description && (
              <Typography 
                variant="body1" 
                color="var(--text-secondary)"
                sx={{ mt: 1 }}
              >
                {playlist.description}
              </Typography>
            )}
          </Box>
          
          {playlist.videos.length > 0 && (
            <Button
              variant="contained"
              startIcon={<PlaylistPlay />}
              onClick={() => handleVideoClick(playlist.videos[0])}
              sx={{
                backgroundColor: 'var(--primary-color)',
                '&:hover': {
                  backgroundColor: 'var(--primary-color-dark)',
                }
              }}
            >
              Play All
            </Button>
          )}
        </Stack>
        
        <Typography 
          variant="subtitle1" 
          color="var(--text-secondary)"
          sx={{ mb: 2 }}
        >
          {playlist.videos.length} {playlist.videos.length === 1 ? 'video' : 'videos'}
        </Typography>
        
        {playlist.videos.length > 0 ? (
          <Paper 
            variant="outlined" 
            sx={{ 
              borderColor: 'var(--border-color)',
              borderRadius: '8px',
              overflow: 'hidden',
              backgroundColor: 'rgba(0, 0, 0, 0.4)'
            }}
          >
            <List disablePadding>
              {playlist.videos.map((video, index) => (
                <Box key={`${video.id?.videoId || video.id}-${index}`}>
                  {index > 0 && <Divider sx={{ borderColor: 'var(--border-color)' }} />}
                  <ListItem 
                    button
                    onClick={() => handleVideoClick(video)}
                    sx={{
                      display: 'flex',
                      gap: 2,
                      '&:hover': {
                        backgroundColor: 'rgba(255, 0, 0, 0.08)'
                      }
                    }}
                  >
                    <Box 
                      component="img"
                      src={getVideoThumbnail(video)}
                      alt={video.snippet?.title}
                      sx={{ 
                        width: 120,
                        height: 68,
                        borderRadius: '4px',
                        objectFit: 'cover'
                      }}
                    />
                    
                    <ListItemText
                      primary={
                        <Typography 
                          color="var(--text-primary)"
                          sx={{
                            display: '-webkit-box',
                            overflow: 'hidden',
                            WebkitBoxOrient: 'vertical',
                            WebkitLineClamp: 2,
                          }}
                        >
                          {video.snippet?.title}
                        </Typography>
                      }
                      secondary={
                        <Typography 
                          variant="body2" 
                          color="var(--text-secondary)"
                          sx={{ mt: 0.5 }}
                        >
                          {video.snippet?.channelTitle}
                        </Typography>
                      }
                    />
                    
                    <ListItemSecondaryAction>
                      <IconButton
                        edge="end"
                        onClick={(e) => handleDeleteDialogOpen(e, video)}
                        sx={{ 
                          color: 'var(--text-secondary)',
                          '&:hover': { color: 'var(--primary-color)' }
                        }}
                      >
                        <Close />
                      </IconButton>
                    </ListItemSecondaryAction>
                  </ListItem>
                </Box>
              ))}
            </List>
          </Paper>
        ) : (
          <Box 
            sx={{ 
              display: 'flex', 
              flexDirection: 'column', 
              alignItems: 'center',
              justifyContent: 'center',
              py: 8,
              color: 'var(--text-secondary)'
            }}
          >
            <PlaylistPlay sx={{ fontSize: 60, mb: 2, opacity: 0.7 }} />
            <Typography variant="h6">No videos in playlist</Typography>
            <Typography variant="body2" sx={{ mt: 1 }}>
              Add videos to your playlist while watching them
            </Typography>
          </Box>
        )}
      </Paper>
      
      {/* Delete Video Dialog */}
      <Dialog
        open={deleteDialogOpen}
        onClose={handleDeleteDialogClose}
        PaperProps={{
          sx: {
            backgroundColor: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
          }
        }}
      >
        <DialogTitle sx={{ color: 'var(--text-primary)' }}>
          Remove from Playlist
        </DialogTitle>
        <DialogContent>
          <Alert severity="warning" sx={{ mb: 2 }}>
            This action cannot be undone.
          </Alert>
          <Typography color="var(--text-secondary)">
            Are you sure you want to remove this video from the playlist?
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button 
            onClick={handleDeleteDialogClose}
            sx={{ color: 'var(--text-secondary)' }}
          >
            Cancel
          </Button>
          <Button 
            onClick={() => handleRemoveVideo(deleteVideoId)}
            color="error"
            variant="contained"
          >
            Remove
          </Button>
        </DialogActions>
      </Dialog>
    </Container>
  );
};

export default PlaylistDetail; 