import { useState } from 'react';
import { 
  Button, 
  IconButton, 
  Menu, 
  MenuItem, 
  ListItemIcon, 
  ListItemText, 
  Divider, 
  Dialog, 
  DialogTitle, 
  DialogContent, 
  DialogActions, 
  TextField, 
  Typography,
  Tooltip,
  Snackbar,
  Alert,
  Box
} from '@mui/material';
import { 
  PlaylistAdd, 
  Add, 
  Check, 
  WatchLater, 
  Favorite,
  Done
} from '@mui/icons-material';
import { usePlaylist } from '../../contexts/PlaylistContext';

const AddToPlaylistButton = ({ video, isIconButton = false }) => {
  const [anchorEl, setAnchorEl] = useState(null);
  const [createDialogOpen, setCreateDialogOpen] = useState(false);
  const [newPlaylistName, setNewPlaylistName] = useState('');
  const [newPlaylistDescription, setNewPlaylistDescription] = useState('');
  const [snackbarOpen, setSnackbarOpen] = useState(false);
  const [snackbarMessage, setSnackbarMessage] = useState('');
  
  const { 
    playlists, 
    createPlaylist, 
    addToPlaylist, 
    removeFromPlaylist, 
    isInPlaylist 
  } = usePlaylist();
  
  const handleClick = (event) => {
    setAnchorEl(event.currentTarget);
  };
  
  const handleClose = () => {
    setAnchorEl(null);
  };
  
  const handleCreateDialogOpen = () => {
    setCreateDialogOpen(true);
    handleClose();
  };
  
  const handleCreateDialogClose = () => {
    setCreateDialogOpen(false);
    setNewPlaylistName('');
    setNewPlaylistDescription('');
  };
  
  const handleCreatePlaylist = () => {
    if (newPlaylistName.trim()) {
      const newPlaylist = createPlaylist(
        newPlaylistName.trim(), 
        newPlaylistDescription.trim()
      );
      
      // Add the video to the new playlist
      addToPlaylist(newPlaylist.id, video);
      
      // Show success message
      setSnackbarMessage(`Added to ${newPlaylistName}`);
      setSnackbarOpen(true);
      
      handleCreateDialogClose();
    }
  };
  
  const handleTogglePlaylist = (playlistId, playlistName) => {
    const wasInPlaylist = isInPlaylist(playlistId, video.id?.videoId || video.id);
    
    if (wasInPlaylist) {
      removeFromPlaylist(playlistId, video.id?.videoId || video.id);
      setSnackbarMessage(`Removed from ${playlistName}`);
    } else {
      addToPlaylist(playlistId, video);
      setSnackbarMessage(`Added to ${playlistName}`);
    }
    
    setSnackbarOpen(true);
  };
  
  const getPlaylistIcon = (playlist) => {
    if (playlist.id === 'watch-later') return <WatchLater />;
    if (playlist.id === 'favorites') return <Favorite />;
    return null;
  };
  
  return (
    <>
      {isIconButton ? (
        <Tooltip title="Save to playlist">
          <IconButton
            onClick={handleClick}
            size="medium"
            sx={{ 
              color: 'var(--text-secondary)',
              '&:hover': { 
                color: 'var(--primary-color)',
                backgroundColor: 'rgba(255, 0, 0, 0.08)'
              }
            }}
          >
            <PlaylistAdd />
          </IconButton>
        </Tooltip>
      ) : (
        <Button
          startIcon={<PlaylistAdd />}
          onClick={handleClick}
          variant="outlined"
          size="small"
          sx={{
            borderColor: 'var(--border-color)',
            color: 'var(--text-secondary)',
            '&:hover': {
              borderColor: 'var(--primary-color)',
              color: 'var(--primary-color)',
              backgroundColor: 'rgba(255, 0, 0, 0.08)'
            }
          }}
        >
          Save
        </Button>
      )}
      
      <Menu
        anchorEl={anchorEl}
        open={Boolean(anchorEl)}
        onClose={handleClose}
        PaperProps={{
          sx: {
            width: 250,
            backgroundColor: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            boxShadow: 'var(--card-hover-shadow)',
            mt: 1
          }
        }}
      >
        <Typography 
          variant="subtitle2" 
          sx={{ 
            px: 2, 
            py: 1, 
            color: 'var(--text-secondary)',
            fontWeight: 500
          }}
        >
          Save to...
        </Typography>
        
        {playlists.map((playlist) => {
          const isVideoInPlaylist = isInPlaylist(playlist.id, video.id?.videoId || video.id);
          
          return (
            <MenuItem 
              key={playlist.id}
              onClick={() => handleTogglePlaylist(playlist.id, playlist.name)}
              sx={{ 
                color: 'var(--text-primary)',
                '&:hover': { backgroundColor: 'rgba(255, 0, 0, 0.08)' },
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                gap: 1
              }}
            >
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                <ListItemIcon sx={{ 
                  color: isVideoInPlaylist 
                    ? 'var(--primary-color)' 
                    : 'var(--text-secondary)',
                  minWidth: 36
                }}>
                  {getPlaylistIcon(playlist) || (
                    isVideoInPlaylist ? <Check /> : <PlaylistAdd />
                  )}
                </ListItemIcon>
                <ListItemText primary={playlist.name} />
              </Box>
              
              {isVideoInPlaylist && (
                <Done 
                  sx={{ 
                    color: 'var(--primary-color)',
                    fontSize: 20,
                    opacity: 0.8
                  }} 
                />
              )}
            </MenuItem>
          );
        })}
        
        <Divider sx={{ my: 1, borderColor: 'var(--border-color)' }} />
        
        <MenuItem 
          onClick={handleCreateDialogOpen}
          sx={{ 
            color: 'var(--text-primary)',
            '&:hover': { backgroundColor: 'rgba(255, 0, 0, 0.08)' }
          }}
        >
          <ListItemIcon sx={{ color: 'var(--text-secondary)' }}>
            <Add />
          </ListItemIcon>
          <ListItemText primary="Create new playlist" />
        </MenuItem>
      </Menu>
      
      {/* Create Playlist Dialog */}
      <Dialog 
        open={createDialogOpen} 
        onClose={handleCreateDialogClose}
        PaperProps={{
          sx: {
            backgroundColor: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            boxShadow: 'var(--card-hover-shadow)',
          }
        }}
      >
        <DialogTitle sx={{ color: 'var(--text-primary)' }}>
          Create new playlist
        </DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            margin="dense"
            label="Name"
            fullWidth
            variant="outlined"
            value={newPlaylistName}
            onChange={(e) => setNewPlaylistName(e.target.value)}
            sx={{
              mb: 2,
              '& .MuiOutlinedInput-root': {
                '& fieldset': {
                  borderColor: 'var(--border-color)',
                },
                '&:hover fieldset': {
                  borderColor: 'var(--text-secondary)',
                },
                '&.Mui-focused fieldset': {
                  borderColor: 'var(--primary-color)',
                },
              },
              '& .MuiInputLabel-root': {
                color: 'var(--text-secondary)',
              },
              '& .MuiInputBase-input': {
                color: 'var(--text-primary)',
              },
            }}
          />
          <TextField
            margin="dense"
            label="Description (optional)"
            fullWidth
            variant="outlined"
            multiline
            rows={2}
            value={newPlaylistDescription}
            onChange={(e) => setNewPlaylistDescription(e.target.value)}
            sx={{
              mb: 2,
              '& .MuiOutlinedInput-root': {
                '& fieldset': {
                  borderColor: 'var(--border-color)',
                },
                '&:hover fieldset': {
                  borderColor: 'var(--text-secondary)',
                },
                '&.Mui-focused fieldset': {
                  borderColor: 'var(--primary-color)',
                },
              },
              '& .MuiInputLabel-root': {
                color: 'var(--text-secondary)',
              },
              '& .MuiInputBase-input': {
                color: 'var(--text-primary)',
              },
            }}
          />
        </DialogContent>
        <DialogActions>
          <Button 
            onClick={handleCreateDialogClose}
            sx={{ color: 'var(--text-secondary)' }}
          >
            Cancel
          </Button>
          <Button 
            onClick={handleCreatePlaylist}
            variant="contained"
            disabled={!newPlaylistName.trim()}
            sx={{
              backgroundColor: 'var(--primary-color)',
              '&:hover': {
                backgroundColor: 'var(--primary-color-dark)',
              },
              '&.Mui-disabled': {
                backgroundColor: 'rgba(255, 0, 0, 0.3)',
              }
            }}
          >
            Create
          </Button>
        </DialogActions>
      </Dialog>
      
      {/* Feedback Snackbar */}
      <Snackbar
        open={snackbarOpen}
        autoHideDuration={2000}
        onClose={() => setSnackbarOpen(false)}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}
      >
        <Alert 
          onClose={() => setSnackbarOpen(false)} 
          severity="success"
          variant="filled"
          sx={{ 
            backgroundColor: 'var(--primary-color)',
            color: 'white'
          }}
        >
          {snackbarMessage}
        </Alert>
      </Snackbar>
    </>
  );
};

export default AddToPlaylistButton; 